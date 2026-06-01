library(testthat)
library(dqcheckr)

base_cfg <- function(rules = list(), column_rules = list()) {
  list(rules = rules, column_rules = column_rules, column_types = list())
}

# -- col_threshold() -----------------------------------------------------------

test_that("col_threshold() returns column-level override when present", {
  cfg <- base_cfg(
    rules        = list(max_missing_rate = 0.05),
    column_rules = list(x = list(max_missing_rate = 0.20))
  )
  expect_equal(col_threshold(cfg, "x", "max_missing_rate", 0.05), 0.20)
})

test_that("col_threshold() falls back to rules-level when no column override", {
  cfg <- base_cfg(rules = list(max_missing_rate = 0.10))
  expect_equal(col_threshold(cfg, "y", "max_missing_rate", 0.05), 0.10)
})

test_that("col_threshold() falls back to default when key absent everywhere", {
  cfg <- base_cfg()
  expect_equal(col_threshold(cfg, "z", "max_missing_rate", 0.05), 0.05)
})

test_that("col_threshold() column override wins over rules-level", {
  cfg <- base_cfg(
    rules        = list(max_missing_rate = 0.10),
    column_rules = list(z = list(max_missing_rate = 0.00))
  )
  expect_equal(col_threshold(cfg, "z", "max_missing_rate", 0.05), 0.00)
})

# -- table_threshold() ---------------------------------------------------------

test_that("table_threshold() returns rules value when present", {
  cfg <- base_cfg(rules = list(min_row_count = 100))
  expect_equal(table_threshold(cfg, "min_row_count", 0), 100)
})

test_that("table_threshold() returns default when key absent", {
  cfg <- base_cfg()
  expect_equal(table_threshold(cfg, "min_row_count", 0), 0)
})

test_that("table_threshold() returns NULL default when no default supplied", {
  cfg <- base_cfg()
  expect_null(table_threshold(cfg, "min_row_count"))
})
