# Optional oracle regeneration only; Python tests/runtime do not require R.
args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", args[grepl("^--file=", args)][1])
root <- normalizePath(file.path(dirname(script), "../../.."), winslash = "/")
calc_dir <- file.path(root, "PA design App/src/modules/calculations")
files <- list.files(calc_dir, pattern = "\\.R$", full.names = TRUE)
for (path in files) source(path)

component <- function(id, type, x, properties = list(label = type)) {
  list(id = id, type = type, x = x, y = 200, properties = properties)
}
edge <- function(from, to) list(from = from, to = to)
cases <- list()
capture <- function(name, components, connections = list(), pin = 20, backoff = 6,
                    architecture = "conventional") {
  cases[[length(cases) + 1]] <<- list(
    name = name,
    document = list(
      components = components, connections = connections, metadata = list(version = "1.0")
    ),
    input_power_dbm = pin, backoff_db = backoff, architecture = architecture,
    expected = lineup_calculate_engine(components, connections, pin, backoff, architecture)
  )
}

capture("linear", list(
  component(10, "transistor", 100, list(label = "Driver", gain = 15, p1db = 50, pae = 40)),
  component(20, "matching", 200, list(loss = 0.5)),
  component(30, "transistor", 300, list(label = "PA", gain = 14, p1db = 60, pae = 55))
))
branched <- jsonlite::read_json(
  file.path(root, "python_app/src/rfview/examples/branched.json"), simplifyVector = FALSE
)
capture("branched_doherty", branched$components, branched$connections, architecture = "doherty")
capture("branched_conventional", branched$components, branched$connections, backoff = 10)
capture("compression", list(
  component(1, "transistor", 100, list(gain = 25, p1db = 30, pae = 50))
), pin = 20, backoff = 1)
capture("dual_operating_points", list(
  component(1, "transistor", 100, list(
    gain = 20, p1db = 50, pout_p3db = 40, pout_pavg = 32,
    pin_p3db = 20, pin_pavg = 14, pae_p3db = 60, pae_pavg = 45
  ))
))
capture("offset_and_termination", list(
  component(100, "termination", 0),
  component(200, "offset_line", 100, list(loss = 0.2, phase_shift_deg = 90, impedance = 35)),
  component(300, "matching", 200, list(loss = 0.3)),
  component(400, "termination", 300)
), list(edge(100, 200), edge(200, 300), edge(300, 400)))
capture("split_terminals", list(
  component(1, "splitter", 100),
  component(2, "matching", 200, list(loss = 0.2)),
  component(3, "matching", 200, list(loss = 0.4))
), list(edge(1, 2), edge(1, 3)))
capture("passive_only", list(component(1, "matching", 100, list(loss = 0.7))))
capture("cw", list(component(1, "transistor", 100, list(p1db = 50))), backoff = 0)
capture("doherty_deep_backoff", list(
  component(1, "transistor", 100, list(label = "Main PA", p1db = 50))
), backoff = 12, architecture = "doherty")
capture("x_sorted", list(
  component(2, "matching", 200, list(loss = 0.7)),
  component(1, "transistor", 100, list(p1db = 50))
))

scalars <- list()
record <- function(name, arguments, value) {
  scalars[[length(scalars) + 1]] <<- list(name = name, arguments = arguments, expected = value)
}
for (f in c(0.1, 0.5, 3, 4, 12, 22, 40, 60, 100)) {
  record("atmospheric_loss", list(f), atm_loss_model(f))
  record("recommend_technology", list(f), recommend_technology(f))
  record("efficiency", list(f, "LDMOS"), eff_ldmos(f))
  record("efficiency", list(f, "GaN"), eff_gan(f))
  record("efficiency", list(f, "SiGe"), eff_sige(f))
  record("available_gain", list(f, 70), calcAvailableGain(f, 70))
  for (type in c("transmission_line", "wilkinson_splitter", "wilkinson_combiner",
                 "quadrature_hybrid", "t_junction", "doherty_combiner", "transformer")) {
    record("passive_loss", list(type, f), estimatePassiveLoss_R(type, f))
  }
}
for (cls in c("A", "AB", "B", "E", "F", "Doherty")) {
  for (bo in c(0, 4, 6, 8, 12, 30)) {
    record("pae_backoff", list(60, bo, cls), calcPAEBackoff(60, bo, cls))
  }
}
for (dbm in c(-30, 0, 30, 47, 55)) {
  record("power_from_dbm", list(dbm), calc_power_from_dbm(dbm))
  watts <- 10^(dbm / 10) / 1000
  record("power_from_watts", list(watts), calc_power_from_watts(watts))
}
record("link_budget", list(43, 15, 15, 10, 3.5, 20, 5, 10),
       calc_link_budget(43, 15, 15, 10, 3.5, 20, 5, 10))
record("power_from_voltage", list(5, 50), calc_power_from_voltage(5, 50))
record("wavelengths", list(3.5, 3.55), calc_wavelengths(3.5, 3.55))
record("sparams", list(0.2, 45), calc_sparams(0.2, 45))
record("thermal", list(10, 50), calc_thermal(10, 50))
record("ropt", list(28, 10, 2), calc_ropt(28, 2, 10)$Ropt_ohm)
record("gate_width", list(10, 2.5, 0.5), calc_gate_width(10, 2.5, 0.5)$gate_width_mm)
for (theta in c(180, 240, 360)) {
  result <- calc_idq_class_ab(800, theta)
  result$formula_str <- NULL
  record("idq", list(800, theta), result)
}
for (topology in c("symmetric", "asymmetric_6dB", "asymmetric_9dB")) {
  result <- calc_doherty_sizing(10, topology)
  result$formula_Zt <- NULL
  record("doherty_sizing", list(10, topology), result)
}
for (z in c(12.5, 100)) {
  result <- calc_matching_lmatch(50, z, 3.5)
  result$formula_str <- NULL
  record("matching_lmatch", list(50, z, 3.5), result)
}
for (r in c(3.38, 10, 50)) {
  result <- calc_doherty_combiner(r, 3.5)
  result$formula_Zt <- NULL
  result$formula_len <- NULL
  record("doherty_combiner", list(r, 3.5), result)
}
destination <- file.path(root, "python_app/tests/fixtures/legacy_reference.json")
dir.create(dirname(destination), showWarnings = FALSE)
canonical_md5 <- function(path) {
  temp <- tempfile()
  on.exit(unlink(temp))
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  writeBin(charToRaw(paste0(paste(lines, collapse = "\n"), "\n")), temp)
  unname(tools::md5sum(temp))
}
jsonlite::write_json(list(
  provenance = list(
    runtime = R.version.string,
    source_md5 = as.list(setNames(vapply(files, canonical_md5, character(1)), basename(files))),
    note = "Generated from current source; known defects are documented, not corrected here."
  ),
  lineups = cases, scalars = scalars
), destination, auto_unbox = TRUE, pretty = TRUE, digits = 16, null = "null")
cat("Exported", length(cases), "lineups and", length(scalars), "scalar cases to", destination, "\n")
