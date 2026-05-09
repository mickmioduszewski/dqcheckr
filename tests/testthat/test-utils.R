library(testthat)
library(dqcheckr)

# ── dq_result() ───────────────────────────────────────────────────────────────

test_that("dq_result() returns a named list with all seven fields", {
  r <- dq_result("QC-01", "Missing rate", column = "name",
                 status = "PASS", observed = "0%", message = "All good")
  expect_type(r, "list")
  expect_named(r, c("check_id", "check_name", "column", "status",
                    "observed", "threshold", "message"), ignore.order = FALSE)
})

test_that("dq_result() defaults column and threshold to NA_character_", {
  r <- dq_result("QC-04", "Row count", status = "INFO",
                 observed = "100", message = "Info only")
  expect_identical(r$column,    NA_character_)
  expect_identical(r$threshold, NA_character_)
})

test_that("dq_result() stops when status is not one of PASS/WARN/FAIL/INFO", {
  expect_error(
    dq_result("QC-01", "Missing rate", status = "ERROR",
              observed = "x", message = "x"),
    regexp = "status"
  )
})

test_that("dq_result() stops on NULL status", {
  expect_error(
    dq_result("QC-01", "Missing rate", status = NULL,
              observed = "x", message = "x")
  )
})

test_that("dq_result() accepts all four valid status values", {
  for (s in c("PASS", "WARN", "FAIL", "INFO")) {
    r <- dq_result("X-01", "test", status = s, observed = "x", message = "x")
    expect_equal(r$status, s)
  }
})

# ── overall_status() ──────────────────────────────────────────────────────────

test_that("overall_status() returns FAIL when any result is FAIL", {
  results <- list(
    dq_result("A", "a", status = "PASS", observed = "x", message = "x"),
    dq_result("B", "b", status = "FAIL", observed = "x", message = "x"),
    dq_result("C", "c", status = "WARN", observed = "x", message = "x")
  )
  expect_equal(overall_status(results), "FAIL")
})

test_that("overall_status() returns WARN when no FAIL but some WARN", {
  results <- list(
    dq_result("A", "a", status = "PASS", observed = "x", message = "x"),
    dq_result("B", "b", status = "WARN", observed = "x", message = "x"),
    dq_result("C", "c", status = "INFO", observed = "x", message = "x")
  )
  expect_equal(overall_status(results), "WARN")
})

test_that("overall_status() returns PASS when only PASS and INFO", {
  results <- list(
    dq_result("A", "a", status = "PASS", observed = "x", message = "x"),
    dq_result("B", "b", status = "INFO", observed = "x", message = "x")
  )
  expect_equal(overall_status(results), "PASS")
})

test_that("overall_status() returns INFO on empty list", {
  expect_equal(overall_status(list()), "INFO")
})

# ── infer_col_type() ──────────────────────────────────────────────────────────

test_that("infer_col_type() returns 'date' for ISO date strings", {
  x <- c("2024-01-01", "2024-06-15", "2023-12-31")
  expect_equal(infer_col_type(x), "date")
})

test_that("infer_col_type() returns 'date' for dd/mm/yyyy format", {
  x <- c("01/01/2024", "15/06/2024", "31/12/2023")
  expect_equal(infer_col_type(x), "date")
})

test_that("infer_col_type() returns 'numeric' when >=90% are numeric", {
  x <- c("1.5", "2.0", "3.1", "abc", rep("4.0", 16))  # 19/20 = 95% numeric
  expect_equal(infer_col_type(x), "numeric")
})

test_that("infer_col_type() returns 'character' when <90% are numeric", {
  x <- c("high", "low", "medium", "1.0", "2.0")  # 40% numeric
  expect_equal(infer_col_type(x), "character")
})

test_that("infer_col_type() returns 'unknown' for all empty/NA", {
  x <- c(NA, "", NA, "")
  expect_equal(infer_col_type(x), "unknown")
})

test_that("infer_col_type() returns 'numeric' for all-NA-except-numeric", {
  x <- c(NA, "1.0", "2.5", NA)
  expect_equal(infer_col_type(x), "numeric")
})

# ── load_config() ─────────────────────────────────────────────────────────────

test_that("load_config() merges rule_overrides over defaults", {
  tmp <- tempdir()
  sub <- file.path(tmp, "cfg_merge_test")
  dir.create(sub, showWarnings = FALSE)
  writeLines(c(
    "default_rules:",
    "  max_missing_rate: 0.05",
    "  min_row_count: 0"
  ), file.path(sub, "dqcheckr.yml"))
  writeLines(c(
    "dataset_name: test_ds",
    "folder: data/",
    "format: csv",
    "rule_overrides:",
    "  max_missing_rate: 0.02"
  ), file.path(sub, "test_ds.yml"))

  cfg <- load_config("test_ds", sub)
  expect_equal(cfg$rules$max_missing_rate, 0.02)
  expect_equal(cfg$rules$min_row_count, 0)
})

test_that("load_config() stops when dqcheckr.yml is missing", {
  tmp <- tempdir()
  sub <- file.path(tmp, "no_global_yml")
  dir.create(sub, showWarnings = FALSE)
  expect_error(load_config("any", sub), regexp = "dqcheckr.yml")
})

test_that("load_config() stops when dataset yml is missing", {
  tmp <- tempdir()
  sub <- file.path(tmp, "no_dataset_yml")
  dir.create(sub, showWarnings = FALSE)
  writeLines(c("default_rules:", "  max_missing_rate: 0.05"),
             file.path(sub, "dqcheckr.yml"))
  expect_error(load_config("nonexistent_ds", sub))
})
