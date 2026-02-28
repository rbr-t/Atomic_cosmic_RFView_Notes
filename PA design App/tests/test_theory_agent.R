# Test: Theory Agent and Theoretical Calculations
# Unit tests for the theoretical calculation module

library(testthat)
library(R6)

# Source the required files
source("../core/ai_agents/base_agent.R")
source("../plugins/rf_pa_design/agents/theory_agent.R")

context("Theory Agent - Theoretical Calculations")

test_that("Theory Agent can be instantiated", {
  agent <- TheoryAgent$new()
  expect_equal(agent$name, "Theory Agent")
  expect_true(grepl("RF fundamentals", agent$expertise))
})

test_that("Load-pull calculation for Class-A is correct", {
  agent <- TheoryAgent$new()
  
  result <- agent$calculate_load_impedance(
    vdd = 28,
    imax = 2,
    architecture = "Class-A"
  )
  
  expect_true(!is.null(result$z_load_ohms))
  expect_true(!is.null(result$pout_watts))
  expect_true(!is.null(result$pae_theoretical))
  
  # Class-A theoretical PAE should be 0.50
  expect_equal(result$pae_theoretical, 0.50)
  
  # Pout should be Vdd * Imax / 2
  expected_pout <- (28 * 2) / 2
  expect_equal(result$pout_watts, expected_pout)
  
  # Zload should be Vdd^2 / (2 * Pout)
  expected_zload <- (28^2) / (2 * expected_pout)
  expect_equal(result$z_load_ohms, expected_zload)
})

test_that("Load-pull calculation for Class-B is correct", {
  agent <- TheoryAgent$new()
  
  result <- agent$calculate_load_impedance(
    vdd = 28,
    imax = 2,
    architecture = "Class-B"
  )
  
  # Class-B theoretical PAE should be ~0.785
  expect_equal(result$pae_theoretical, 0.785, tolerance = 0.001)
  
  # Class-B Pout should be higher than Class-A for same Vdd/Imax
  expect_true(result$pout_watts > 28)
})

test_that("Matching network synthesis - step-down", {
  agent <- TheoryAgent$new()
  
  result <- agent$synthesize_matching_network(
    z_source = 50,
    z_load = 10,
    freq_ghz = 2.4,
    type = "L-section"
  )
  
  expect_equal(result$type, "L-section step-down")
  expect_true(!is.null(result$series_inductor_nh))
  expect_true(!is.null(result$shunt_capacitor_pf))
  expect_true(result$q_factor > 0)
  
  # Q = sqrt(Zsource/Zload - 1)
  expected_q <- sqrt(50/10 - 1)
  expect_equal(result$q_factor, expected_q, tolerance = 0.01)
})

test_that("Matching network synthesis - step-up", {
  agent <- TheoryAgent$new()
  
  result <- agent$synthesize_matching_network(
    z_source = 10,
    z_load = 50,
    freq_ghz = 2.4,
    type = "L-section"
  )
  
  expect_equal(result$type, "L-section step-up")
  expect_true(!is.null(result$series_capacitor_pf))
  expect_true(!is.null(result$shunt_inductor_nh))
  
  # Q = sqrt(Zload/Zsource - 1)
  expected_q <- sqrt(50/10 - 1)
  expect_equal(result$q_factor, expected_q, tolerance = 0.01)
})

test_that("Bode-Fano limit check works", {
  agent <- TheoryAgent$new()
  
  result <- agent$check_bode_fano_limit(
    q_load = 10,
    z_ratio = 5,
    freq_ghz = 2.4,
    bandwidth_pct = 10
  )
  
  expect_true(!is.null(result$vswr_limit))
  expect_true(!is.null(result$max_reflection_coeff))
  expect_true(!is.null(result$feasible))
  
  # High Q with narrow bandwidth should be feasible
  expect_true(result$feasible)
})

test_that("Theory Agent execute method returns valid structure", {
  agent <- TheoryAgent$new()
  
  task <- list(
    query = "What is the theoretical PAE limit for Class-A?",
    context = list(
      frequency = 2.4,
      architecture = "Class-A"
    )
  )
  
  result <- agent$execute(task)
  
  expect_true(!is.null(result$answer))
  expect_true(!is.null(result$confidence))
  expect_true(is.numeric(result$confidence))
  expect_true(result$confidence >= 0 && result$confidence <= 1)
})

# Run tests
test_dir(".", reporter = "summary")
