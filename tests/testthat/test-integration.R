library(testthat)
library(dqcheckr)

# End-to-end: run_dq_check() against fixture files in a temp config directory.
# This test wires up real YAML configs and calls the full pipeline.

setup_integration_env <- function() {
  tmp <- tempdir()
  cfg <- file.path(tmp, "dq_integration")
  dir.create(cfg, showWarnings = FALSE)

  writeLines(c(
    "snapshot_db: 'data/snapshots.sqlite'",
    "report_output_dir: 'reports/'",
    "default_rules:",
    "  max_missing_rate: 0.05",
    "  max_non_numeric_rate: 0.01",
    "  min_row_count: 0",
    "  max_row_count_change_pct: 0.10",
    "  max_numeric_mean_shift_pct: 0.20",
    "  max_missing_rate_change_pp: 2.0",
    "  max_non_numeric_rate_change_pp: 1.0",
    "  flag_new_columns: true",
    "  flag_dropped_columns: true",
    "  flag_type_changes: true",
    "  flag_column_order_change: true"
  ), file.path(cfg, "dqcheckr.yml"))

  fix_curr <- testthat::test_path("fixtures", "valid_accounts_current.csv")
  fix_prev <- testthat::test_path("fixtures", "valid_accounts_previous.csv")

  writeLines(c(
    "dataset_name: 'integ_ds'",
    sprintf("current_file: '%s'", fix_curr),
    sprintf("previous_file: '%s'", fix_prev),
    "format: csv",
    "encoding: UTF-8",
    sprintf("snapshot_db: '%s'", file.path(cfg, "snapshots.sqlite")),
    sprintf("report_output_dir: '%s'", file.path(cfg, "reports"))
  ), file.path(cfg, "integ_ds.yml"))

  cfg
}

test_that("run_dq_check() returns a list with status, report_path, snapshot_id", {
  cfg_dir <- setup_integration_env()
  result  <- suppressWarnings(
    run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE)
  )
  expect_type(result, "list")
  expect_named(result, c("status", "report_path", "snapshot_id"), ignore.order = FALSE)
  expect_true(result$status %in% c("PASS", "WARN", "FAIL", "INFO"))
})

test_that("run_dq_check() writes an HTML report file to disk", {
  skip_if_not(quarto::quarto_available(), "Quarto CLI not available")
  cfg_dir <- setup_integration_env()
  result  <- run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE)
  expect_false(is.null(result$report_path))
  expect_true(file.exists(result$report_path))
  expect_match(result$report_path, "\\.html$")
})

test_that("run_dq_check() writes a snapshot to the SQLite database", {
  cfg_dir <- setup_integration_env()
  result  <- suppressWarnings(
    run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE)
  )
  expect_false(is.null(result$snapshot_id))
  expect_true(result$snapshot_id >= 1)
})

test_that("run_dq_check() returns PASS status for the clean fixture pair", {
  cfg_dir <- setup_integration_env()
  result  <- suppressWarnings(
    run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE)
  )
  expect_equal(result$status, "PASS")
})
