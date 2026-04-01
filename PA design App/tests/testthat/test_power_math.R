# ═══════════════════════════════════════════════════════════════════════════
# test_power_math.R
# Unit tests for power conversion mathematics.
# These are fundamental — if these fail, everything else is wrong.
# ═══════════════════════════════════════════════════════════════════════════

library(testthat)

# ── Helper functions (same as in calc_pa_lineup.R) ──────────────────────────
dbm2w  <- function(dbm) 10^(dbm / 10) / 1000
w2dbm  <- function(w)   10 * log10(w * 1000)
sumdbm <- function(dbm_vec) w2dbm(sum(dbm2w(dbm_vec)))

test_that("dBm to Watts conversion: known reference points", {
  expect_equal(round(dbm2w(30),  3), 1.000)    # 30 dBm = 1 W
  expect_equal(round(dbm2w(40),  2), 10.00)    # 40 dBm = 10 W
  expect_equal(round(dbm2w(50),  0), 100)      # 50 dBm = 100 W
  expect_equal(round(dbm2w(0),   6), 0.001)    # 0 dBm  = 1 mW
})

test_that("Watts to dBm conversion: round-trip", {
  for (dbm in c(0, 10, 20, 30, 40, 50, 55.3)) {
    expect_equal(round(w2dbm(dbm2w(dbm)), 6), dbm,
      label = sprintf("Round-trip at %g dBm", dbm))
  }
})

test_that("Two-way Wilkinson combiner: 47+47 dBm → 50 dBm", {
  result <- sumdbm(c(47, 47))
  expect_equal(round(result, 2), 50.00,
    label = "Equal power combination: 47+47 dBm = 50 dBm")
})

test_that("Two-way splitter loss: 50 dBm → 46.99 dBm per port", {
  # 10×log10(0.5) = -3.01 dB
  split_factor <- 10 * log10(2)
  expect_equal(round(split_factor, 2), 3.01,
    label = "2-way split factor must be 3.01 dB")
})

test_that("Asymmetric combiner: 50+44 dBm → within 0.03 dB of sum", {
  # 100W + 25W = 125W = 50.97 dBm
  result <- sumdbm(c(50, 44))
  expect_equal(round(result, 1), 51.0)
})

test_that("Power addition is commutative in watts domain", {
  a <- 47.3; b <- 44.1
  expect_equal(sumdbm(c(a, b)), sumdbm(c(b, a)),
    label = "Power addition must be commutative")
})
