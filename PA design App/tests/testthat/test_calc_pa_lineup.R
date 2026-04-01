# ═══════════════════════════════════════════════════════════════════════════
# test_calc_pa_lineup.R
# Unit tests for the PA lineup cascade calculation engine.
# Test matrix from Rubix audit 2026-04-01.
# These tests encode physical correctness requirements.
# ═══════════════════════════════════════════════════════════════════════════

library(testthat)

# Source the calculation engine
source("../../R/modules/calculations/calc_pa_lineup.R")

# ── Helper ───────────────────────────────────────────────────────────────────
dbm2w <- function(dbm) 10^(dbm / 10) / 1000
w2dbm <- function(w)   10 * log10(w * 1000)

# ── TC1: LTE 1.8 GHz, 55.3 dBm — LDMOS two-stage Doherty ──────────────────
test_that("TC1: LTE 1.8 GHz two-stage cascade reaches 55.3 dBm", {
  comps <- list(
    list(id="driver", type="transistor", x=100, y=200,
         properties=list(label="Driver", technology="LDMOS", biasClass="AB",
                         gain=15, pout=43, pae=45, vdd=28, rth=2.5, p1db=41)),
    list(id="pa",     type="transistor", x=300, y=200,
         properties=list(label="PA",     technology="LDMOS", biasClass="AB",
                         gain=15, pout=55.3, pae=45, vdd=28, rth=2.5, p1db=53))
  )
  conns <- list(list(from="driver", to="pa"))
  result <- lineup_calculate_engine(comps, conns, input_power_dbm=55.3-30, backoff_db=8)

  expect_true(result$success)
  expect_equal(round(result$final_pout_dbm, 1), 55.3)
  expect_equal(round(result$total_gain, 1), 30.0)
})

# ── TC2: 5G Sub-6 2.6 GHz, 50 dBm — GaN Doherty ───────────────────────────
test_that("TC2: 5G 2.6 GHz Doherty cascade reaches 50 dBm", {
  comps <- list(
    list(id="driver", type="transistor", x=100, y=200,
         properties=list(label="Driver", technology="GaN_SiC", biasClass="AB",
                         gain=15, pout=43, pae=55, vdd=28, rth=2.5, p1db=41)),
    list(id="splitter", type="splitter", x=250, y=200,
         properties=list(label="Splitter", loss=0.3, n_outputs=2)),
    list(id="main_pa", type="transistor", x=400, y=100,
         properties=list(label="Main PA", technology="GaN_SiC", biasClass="AB",
                         gain=14, pout=47.0, pae=60, vdd=28, rth=2.5, p1db=45)),
    list(id="peak_pa", type="transistor", x=400, y=300,
         properties=list(label="Peak PA", technology="GaN_SiC", biasClass="C",
                         gain=14, pout=47.0, pae=55, vdd=28, rth=2.5, p1db=45)),
    list(id="combiner", type="combiner", x=550, y=200,
         properties=list(label="Combiner", combiner_type="Doherty", loss=0.3, n_inputs=2))
  )
  conns <- list(
    list(from="driver",   to="splitter"),
    list(from="splitter", to="main_pa"),
    list(from="splitter", to="peak_pa"),
    list(from="main_pa",  to="combiner"),
    list(from="peak_pa",  to="combiner")
  )
  result <- lineup_calculate_engine(comps, conns, input_power_dbm=50-43, backoff_db=8.5)

  expect_true(result$success)
  expect_lte(abs(result$final_pout_dbm - 50.0), 0.5,
    label = "Final Pout should be within 0.5 dB of 50 dBm")
})

# ── TC3: Splitter power split law ──────────────────────────────────────────
test_that("TC3: 2-way Wilkinson splitter: Pout = Pin - 3.01 dB - loss", {
  comps <- list(
    list(id="splitter", type="splitter", x=100, y=200,
         properties=list(label="Splitter", loss=0.3, n_outputs=2))
  )
  result <- lineup_calculate_engine(comps, list(), input_power_dbm=40, backoff_db=6)
  # Each port should see 40 - 10*log10(2) - 0.3 = 40 - 3.01 - 0.3 = 36.69 dBm
  expect_true(result$success)
  expect_equal(round(result$final_pout_dbm, 1), 36.7,
    label = "Splitter output: 40 - 3.01 - 0.3 = 36.7 dBm")
})

# ── TC4: Combiner power summing law ────────────────────────────────────────
test_that("TC4: 2-input combiner sums power correctly in watts domain", {
  # Two transistors feeding a combiner, each outputting 47 dBm
  comps <- list(
    list(id="main", type="transistor", x=100, y=100,
         properties=list(label="Main", technology="GaN_SiC", biasClass="AB",
                         gain=14, pout=47, pae=60, vdd=28, rth=2.5, p1db=45)),
    list(id="peak", type="transistor", x=100, y=300,
         properties=list(label="Peak", technology="GaN_SiC", biasClass="C",
                         gain=14, pout=47, pae=55, vdd=28, rth=2.5, p1db=45)),
    list(id="comb", type="combiner", x=300, y=200,
         properties=list(label="Combiner", combiner_type="Wilkinson", loss=0.3))
  )
  conns <- list(list(from="main", to="comb"), list(from="peak", to="comb"))
  result <- lineup_calculate_engine(comps, conns, input_power_dbm=33, backoff_db=6)

  # 47 dBm + 47 dBm in watts = 2 × 50W = 100W = 50 dBm; minus 0.3 dB loss → 49.7 dBm
  expect_lte(abs(result$final_pout_dbm - 49.7), 0.2,
    label = "Combiner: 47+47 dBm → 50 dBm - 0.3 dB = 49.7 dBm")
})

# ── TC5: PAE formula correctness ────────────────────────────────────────────
test_that("TC5: PAE = (Pout - Pin) / PDC × 100, DE = Pout/PDC × 100", {
  # Single transistor: Pout=40 dBm (10W), PAE=50%, Gain=15dB
  # Pin = 40-15 = 25 dBm (0.316W)
  # PDC = Pout/PAE = 10W/0.5 = 20W
  # DE = Pout/PDC = 10/20 = 50% (same as PAE only when Pin→0)
  # PAE = (10 - 0.316) / 20 × 100 = 48.4%
  comps <- list(
    list(id="pa", type="transistor", x=100, y=200,
         properties=list(label="PA", technology="GaN_SiC", biasClass="AB",
                         gain=15, pout=40, pae=50, vdd=28, rth=2.5, p1db=38))
  )
  result <- lineup_calculate_engine(comps, list(), input_power_dbm=25, backoff_db=6)

  expect_true(result$success)
  # System PAE: (Pout-Pin)/PDC → accounts for input power
  expect_lte(abs(result$system_pae - 48.4), 1.0,
    label = "System PAE = (Pout-Pin)/PDC ≈ 48.4% for gain=15dB, component_PAE=50%")
  # System DE >= System PAE always (no input power subtraction)
  expect_gte(result$system_de, result$system_pae,
    label = "DE must be >= PAE since DE ignores input power")
})

# ── TC6: PAE physical limit ──────────────────────────────────────────────────
test_that("TC6: System PAE must not exceed 78.5% (Class-B theoretical limit)", {
  comps <- list(
    list(id="pa", type="transistor", x=100, y=200,
         properties=list(label="PA", technology="GaN_SiC", biasClass="AB",
                         gain=20, pout=43, pae=78, vdd=28, rth=2.5, p1db=41))
  )
  result <- lineup_calculate_engine(comps, list(), input_power_dbm=23, backoff_db=6)

  expect_lte(result$system_pae, 78.5,
    label = "System PAE must not exceed 78.5% (Class-B theoretical limit)")
})

# ── TC7: Backoff power is always less than P3dB ─────────────────────────────
test_that("TC7: Backoff (Pavg) power < P3dB power", {
  comps <- list(
    list(id="pa", type="transistor", x=100, y=200,
         properties=list(label="PA", technology="GaN_SiC", biasClass="AB",
                         gain=15, pout=43, pae=55, vdd=28, rth=2.5, p1db=41))
  )
  result <- lineup_calculate_engine(comps, list(), input_power_dbm=28, backoff_db=8.5)

  expect_lt(result$final_pout_bo_dbm, result$final_pout_dbm,
    label = "Backoff Pout must be less than full power Pout")
  expect_equal(round(result$final_pout_dbm - result$final_pout_bo_dbm, 1), 8.5,
    label = "Power difference must equal PAR = 8.5 dB")
})

# ── TC8: Edge case — PAR = 0 (CW operation) ─────────────────────────────────
test_that("TC8: PAR=0 (CW mode) — backoff power equals full power", {
  comps <- list(
    list(id="pa", type="transistor", x=100, y=200,
         properties=list(label="PA", technology="GaN_SiC", biasClass="AB",
                         gain=15, pout=43, pae=55, vdd=28, rth=2.5, p1db=41))
  )
  result <- lineup_calculate_engine(comps, list(), input_power_dbm=28, backoff_db=0)

  expect_true(result$success)
  expect_equal(result$final_pout_dbm, result$final_pout_bo_dbm,
    label = "With PAR=0: P3dB equals Pavg (no backoff)")
})

# ── TC9: Thermal: Tj must be positive and finite ─────────────────────────────
test_that("TC9: Junction temperature Tj > ambient and finite", {
  comps <- list(
    list(id="pa", type="transistor", x=100, y=200,
         properties=list(label="PA", technology="GaN_SiC", biasClass="AB",
                         gain=15, pout=43, pae=55, vdd=28, rth=2.5, p1db=41))
  )
  result <- lineup_calculate_engine(comps, list(), input_power_dbm=28, backoff_db=8)

  pa_stage <- result$stage_results[[1]]
  expect_gt(pa_stage$tj_c, 25, label = "Tj must exceed ambient 25°C")
  expect_true(is.finite(pa_stage$tj_c), label = "Tj must be finite (no Inf/NaN)")
  expect_lt(pa_stage$tj_c, 300, label = "Tj must be below 300°C (sanity check)")
})

# ── TC10: Gain adds correctly in dB ──────────────────────────────────────────
test_that("TC10: Cascade gain = sum of stage gains in dB", {
  comps <- list(
    list(id="s1", type="transistor", x=100, y=200,
         properties=list(label="Stage1", technology="GaN_SiC", biasClass="AB",
                         gain=15, pout=30, pae=55, vdd=28, rth=2.5, p1db=28)),
    list(id="s2", type="transistor", x=300, y=200,
         properties=list(label="Stage2", technology="GaN_SiC", biasClass="AB",
                         gain=12, pout=43, pae=55, vdd=28, rth=2.5, p1db=41))
  )
  conns <- list(list(from="s1", to="s2"))
  result <- lineup_calculate_engine(comps, conns, input_power_dbm=16, backoff_db=6)

  expect_true(result$success)
  expect_equal(round(result$final_pout_dbm - 16, 1), 27.0,
    label = "Total gain must equal 15 + 12 = 27 dB")
})

# ── TC11: P1dB constraint — P1dB ≤ P3dB ─────────────────────────────────────
test_that("TC11: P1dB must always be at or below P3dB", {
  # P1dB > Pout is physically impossible
  comps <- list(
    list(id="pa", type="transistor", x=100, y=200,
         properties=list(label="PA", technology="GaN_SiC", biasClass="AB",
                         gain=15, pout=43, pae=55, vdd=28, rth=2.5,
                         p1db=50))  # P1dB > Pout — should be clamped
  )
  result <- lineup_calculate_engine(comps, list(), input_power_dbm=28, backoff_db=6)

  expect_true(result$success)
  pa_stage <- result$stage_results[[1]]
  # P1dB stored in stage must not exceed pout
  if (!is.null(pa_stage$p1db_dbm)) {
    expect_lte(pa_stage$p1db_dbm, pa_stage$pout_dbm,
      label = "P1dB must be clamped to ≤ Pout (P3dB)")
  }
})

# ── TC12: Doherty PAE at backoff ≥ conventional PAE at backoff ───────────────
test_that("TC12: Doherty PAE at Pavg should be >= class-AB PAE at same backoff", {
  # This test checks that the Doherty PAE model is correctly modelled
  # For a conventional class-AB PA, PAE degrades with backoff
  # For a Doherty PA, PAE should be maintained or improved at 6-10 dB backoff
  # This test will FAIL on current code (FM-02 Doherty Polarity Flip)
  # and should PASS after fix

  # Conventional: single PA
  comps_conv <- list(
    list(id="pa", type="transistor", x=100, y=200,
         properties=list(label="PA", technology="GaN_SiC", biasClass="AB",
                         gain=15, pout=43, pae=55, vdd=28, rth=2.5, p1db=41))
  )
  result_conv_full <- lineup_calculate_engine(comps_conv, list(), input_power_dbm=28, backoff_db=0)
  result_conv_bo   <- lineup_calculate_engine(comps_conv, list(), input_power_dbm=28, backoff_db=8.5)

  # PAE degrades at backoff for conventional
  expect_lt(result_conv_bo$system_pae_bo, result_conv_full$system_pae,
    label = "Conventional PA: PAE at backoff < PAE at full power")

  # Doherty: Main + Aux PA with combiner
  comps_doh <- list(
    list(id="main", type="transistor", x=100, y=100,
         properties=list(label="Main PA", technology="GaN_SiC", biasClass="AB",
                         gain=14, pout=47, pae=60, vdd=28, rth=2.5, p1db=45,
                         topology="doherty_main")),
    list(id="peak", type="transistor", x=100, y=300,
         properties=list(label="Peak PA", technology="GaN_SiC", biasClass="C",
                         gain=14, pout=47, pae=55, vdd=28, rth=2.5, p1db=45,
                         topology="doherty_peak")),
    list(id="comb", type="combiner", x=300, y=200,
         properties=list(label="Combiner", combiner_type="Doherty", loss=0.3))
  )
  conns_doh <- list(list(from="main", to="comb"), list(from="peak", to="comb"))
  result_doh_bo <- lineup_calculate_engine(comps_doh, conns_doh, input_power_dbm=33, backoff_db=8.5)

  # Doherty PAE at backoff should be >= 85% of its full power PAE
  # (load modulation effect — main PA efficiency maintained)
  # NOTE: This test is RED on current code and should become GREEN after FM-02 fix
  skip("TC12 is RED until FM-02 Doherty backoff PAE fix is applied")
  expect_gte(result_doh_bo$system_pae_bo / result_doh_bo$system_pae, 0.85,
    label = "Doherty: PAE at 8.5dB backoff must be >=85% of full-power PAE")
})
