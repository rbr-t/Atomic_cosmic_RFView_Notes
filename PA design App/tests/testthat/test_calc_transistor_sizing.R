# ═══════════════════════════════════════════════════════════════════════════
# test_calc_transistor_sizing.R
# Unit tests for transistor sizing calculations.
# ═══════════════════════════════════════════════════════════════════════════

library(testthat)

source("../../R/modules/calculations/calc_transistor_sizing.R")

# ── Ropt tests ───────────────────────────────────────────────────────────────

test_that("Ropt: GaN reference point (28V, Vknee=2V, 10W)", {
  r <- calc_ropt(28, 2, 10)
  # (28-2)^2 / (2×10) = 676/20 = 33.8 Ω
  expect_equal(round(r$Ropt_ohm, 1), 33.8)
})

test_that("Ropt: LDMOS reference point (28V, Vknee=3V, 100W)", {
  r <- calc_ropt(28, 3, 100)
  # (28-3)^2 / (2×100) = 625/200 = 3.125 Ω
  expect_equal(round(r$Ropt_ohm, 3), 3.125)
})

test_that("Ropt: Vknee=0 gives Vdd^2/(2P)", {
  r <- calc_ropt(28, 0, 10)
  # (28)^2 / (2×10) = 784/20 = 39.2 Ω
  expect_equal(round(r$Ropt_ohm, 1), 39.2)
  # This verifies the simplified formula is a special case of the correct one
})

test_that("Ropt: GaN 28V 100W/PA Doherty stage", {
  r <- calc_ropt(28, 2, 100)
  # (26)^2 / (2×100) = 676/200 = 3.38 Ω
  expect_equal(round(r$Ropt_ohm, 2), 3.38)
})

test_that("Ropt: Pout=0 returns NA with warning", {
  r <- calc_ropt(28, 2, 0)
  expect_true(is.na(r$Ropt_ohm))
  expect_true(!is.null(r$warning))
})

test_that("Ropt: Pout negative returns NA with warning", {
  r <- calc_ropt(28, 2, -5)
  expect_true(is.na(r$Ropt_ohm))
})

# ── Doherty sizing tests ─────────────────────────────────────────────────────

test_that("Doherty symmetric: Ropt_peak = 2×Ropt_main", {
  d <- calc_doherty_sizing(10, "symmetric")
  expect_equal(d$Ropt_peak_ohm, 20)
  expect_equal(d$gate_ratio, 1.0)
})

test_that("Doherty Zt: √(Ropt_main × 50)", {
  d <- calc_doherty_sizing(10, "symmetric")
  expect_equal(round(d$Zt_ohm, 3), round(sqrt(10 * 50), 3))
})

test_that("Doherty Zt reference: Ropt_main=3.38Ω → Zt=13.0Ω", {
  d <- calc_doherty_sizing(3.38, "symmetric")
  # √(3.38 × 50) = √169 = 13.0
  expect_equal(round(d$Zt_ohm, 1), 13.0)
})

# ── L-match tests ────────────────────────────────────────────────────────────

test_that("L-match: Zs=Zl returns Q=0 and topology=none", {
  m <- calc_matching_lmatch(50, 50, 2.6)
  expect_equal(m$Q, 0)
  expect_equal(m$topology, "none")
})

test_that("L-match Q factor: √(max/min - 1)", {
  m <- calc_matching_lmatch(50, 12.5, 2.6)
  # Q = √(50/12.5 - 1) = √3 = 1.732
  expect_equal(round(m$Q, 3), 1.732)
})

# ── Gate width tests ─────────────────────────────────────────────────────────

test_that("Gate width: GaN 10W at 50% PAE, 2.5 W/mm", {
  gw <- calc_gate_width(10, 2.5, 0.5)
  # W = 10 / (2.5 × 0.5) = 8.0 mm
  expect_equal(gw$gate_width_mm, 8.0)
})

test_that("Gate width: zero power_density returns NA", {
  gw <- calc_gate_width(10, 0, 0.5)
  expect_true(is.na(gw$gate_width_mm))
})
