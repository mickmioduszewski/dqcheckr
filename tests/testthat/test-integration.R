
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
  skip_on_cran()   # renders via Quarto when available — keep CRAN wall time bounded
  cfg_dir <- setup_integration_env()
  result  <- suppressWarnings(
    run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE)
  )
  expect_type(result, "list")
  expect_named(result, c("status", "report_path", "snapshot_id"), ignore.order = FALSE)
  expect_true(result$status %in% c("PASS", "WARN", "FAIL", "INFO"))
})

test_that("run_dq_check() writes an HTML report file to disk", {
  skip_on_cran()   # renders via Quarto when available — keep CRAN wall time bounded
  skip_if_not(quarto::quarto_available(), "Quarto CLI not available")
  cfg_dir <- setup_integration_env()
  result  <- run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE)
  expect_false(is.null(result$report_path))
  expect_true(file.exists(result$report_path))
  expect_match(result$report_path, "\\.html$")
})

test_that("run_dq_check() writes a snapshot to the SQLite database", {
  skip_on_cran()   # renders via Quarto when available — keep CRAN wall time bounded
  cfg_dir <- setup_integration_env()
  result  <- suppressWarnings(
    run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE)
  )
  expect_false(is.null(result$snapshot_id))
  expect_true(result$snapshot_id >= 1)
})

test_that("run_dq_check() returns PASS status for the clean fixture pair", {
  skip_on_cran()   # renders via Quarto when available — keep CRAN wall time bounded
  cfg_dir <- setup_integration_env()
  result  <- suppressWarnings(
    run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE)
  )
  expect_equal(result$status, "PASS")
})

# -- Empty (header-only) delivery completes with FAIL (0.2.3, B-01) ---------------

test_that("run_dq_check() completes with FAIL for an empty (header-only) delivery", {
  skip_on_cran()   # renders via Quarto when available — keep CRAN wall time bounded
  tmp <- tempdir()
  cfg <- file.path(tmp, "dq_empty_integ")
  dir.create(cfg, showWarnings = FALSE)
  on.exit(unlink(cfg, recursive = TRUE))

  empty_csv <- file.path(cfg, "empty_delivery.csv")
  writeLines("id,name,amount", empty_csv)                # header only, 0 data rows

  writeLines(c(
    "default_rules:",
    "  max_missing_rate: 0.05"
  ), file.path(cfg, "dqcheckr.yml"))
  writeLines(c(
    "dataset_name: 'empty_ds'",
    sprintf("current_file: '%s'", empty_csv),
    "format: csv",
    sprintf("snapshot_db: '%s'", file.path(cfg, "snapshots.sqlite")),
    sprintf("report_output_dir: '%s'", file.path(cfg, "reports"))
  ), file.path(cfg, "empty_ds.yml"))

  result <- suppressWarnings(
    run_dq_check("empty_ds", config_dir = cfg, open_report = FALSE)
  )
  expect_equal(result$status, "FAIL")                    # reported, not crashed
  expect_false(is.null(result$snapshot_id))              # snapshot was written
})

# -- A lost snapshot is surfaced, not announced as success (B-08) -----------------

test_that("run_dq_check() flags a lost snapshot on its result line (B-08)", {
  skip_on_cran()
  cfg_dir <- setup_integration_env()

  # Force the snapshot write to fail: point snapshot_db under a path whose parent
  # is a regular file, so the database cannot be created.
  fake <- tempfile()
  file.create(fake)
  on.exit(unlink(fake))
  impossible <- file.path(fake, "nope.sqlite")

  writeLines(c(
    "dataset_name: 'integ_ds'",
    sprintf("current_file: '%s'",
            testthat::test_path("fixtures", "valid_accounts_current.csv")),
    sprintf("previous_file: '%s'",
            testthat::test_path("fixtures", "valid_accounts_previous.csv")),
    "format: csv", "encoding: UTF-8",
    sprintf("snapshot_db: '%s'", impossible),
    sprintf("report_output_dir: '%s'", file.path(cfg_dir, "reports"))
  ), file.path(cfg_dir, "integ_ds.yml"))

  expect_message(
    suppressWarnings(
      run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE)),
    regexp = "snapshot NOT recorded"
  )
})

# -- Render-failure path is reconciled into the snapshot (B-05/06/28/12/34) -------
# When no report is written, the snapshot must not keep render_status='success'
# and an optimistic report_file naming a file that does not exist -- consumers
# (read_recent_snapshots, the GUI history link) would advertise a dead report.

test_that("run_dq_check() marks the snapshot render-failed when Quarto is absent", {
  skip_on_cran()
  # Force the Quarto-unavailable branch regardless of the host, so this runs
  # everywhere and does not depend on Quarto being uninstalled.
  testthat::local_mocked_bindings(
    quarto_available = function(...) FALSE, .package = "quarto")

  cfg_dir <- setup_integration_env()
  expect_warning(
    result <- run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE),
    regexp = "Quarto"
  )

  # The run still completes and records a snapshot -- only the report is absent.
  expect_null(result$report_path)
  expect_false(is.null(result$snapshot_id))

  snaps <- read_recent_snapshots(file.path(cfg_dir, "snapshots.sqlite"),
                                 "integ_ds", n = 1)
  expect_equal(snaps$render_status[1], "failed")     # guard fires
  expect_true(is.na(snaps$report_file[1]))           # no phantom filename
})

test_that("run_dq_check() warns and reconciles when render_report() throws (B-28)", {
  skip_on_cran()
  # The Quarto-absent (skipped) path is covered above; this exercises the other
  # NULL-report branch -- render_report() actually raising an error.
  testthat::local_mocked_bindings(
    render_report = function(...) stop("simulated render explosion"))

  cfg_dir <- setup_integration_env()
  expect_warning(
    result <- run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE),
    regexp = "Report rendering failed"
  )
  expect_null(result$report_path)
  expect_false(is.null(result$snapshot_id))

  snaps <- read_recent_snapshots(file.path(cfg_dir, "snapshots.sqlite"),
                                 "integ_ds", n = 1)
  expect_equal(snaps$render_status[1], "failed")   # reconciled, not left success
  expect_true(is.na(snaps$report_file[1]))
})

test_that("run_dq_check() records report_file only for a report that exists", {
  skip_on_cran()
  skip_if_not(quarto::quarto_available(), "Quarto CLI not available")
  cfg_dir <- setup_integration_env()
  result  <- run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE)

  snaps <- read_recent_snapshots(file.path(cfg_dir, "snapshots.sqlite"),
                                 "integ_ds", n = 1)
  expect_equal(snaps$render_status[1], "success")
  expect_false(is.na(snaps$report_file[1]))
  # report_file names the file that was actually written.
  expect_true(file.exists(file.path(cfg_dir, "reports", snaps$report_file[1])))
  expect_equal(basename(result$report_path), snaps$report_file[1])
})

# -- Report filename: timestamp slug + snapshot id (0.2.3 B-04; 0.2.5 B-42) --------

test_that("report filename is the run_timestamp slug plus the snapshot id", {
  skip_on_cran()   # renders via Quarto when available — keep CRAN wall time bounded
  cfg_dir <- setup_integration_env()
  result  <- suppressWarnings(
    run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE)
  )
  skip_if(is.null(result$report_path), "Report not rendered (Quarto unavailable)")

  snaps <- read_recent_snapshots(file.path(cfg_dir, "snapshots.sqlite"),
                                 "integ_ds", n = 1)
  # slug = the UTC timestamp, then the snapshot id (B-42 uniqueness).
  ts_raw <- gsub("[^0-9]", "", substr(snaps$run_timestamp[1], 1, 19))
  slug   <- paste0(substr(ts_raw, 1, 8), "_", substr(ts_raw, 9, 14))
  expect_equal(basename(result$report_path),
               sprintf("integ_ds_%s_%d.html", slug, snaps$id[1]))
  # The stored report_file matches the file actually written.
  expect_equal(snaps$report_file[1], basename(result$report_path))
})

test_that("two same-second runs get distinct report files, neither overwritten (B-42)", {
  skip_on_cran()
  skip_if_not(quarto::quarto_available(), "Quarto CLI not available")
  cfg_dir <- setup_integration_env()

  # Freeze the clock so both runs stamp the identical wall-clock second; only the
  # snapshot id distinguishes them.
  fixed <- as.POSIXct("2026-07-18 01:02:03", tz = "UTC")
  testthat::local_mocked_bindings(Sys.time = function() fixed, .package = "base")

  r1 <- run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE)
  r2 <- run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE)

  expect_false(is.null(r1$report_path))
  expect_false(is.null(r2$report_path))
  # Distinct filenames -> run 1's report was not clobbered by run 2.
  expect_false(basename(r1$report_path) == basename(r2$report_path))
  expect_true(file.exists(r1$report_path))
  expect_true(file.exists(r2$report_path))

  # Each snapshot row links to its own report.
  snaps <- read_recent_snapshots(file.path(cfg_dir, "snapshots.sqlite"),
                                 "integ_ds", n = 2)
  expect_equal(nrow(snaps), 2L)
  expect_equal(length(unique(snaps$report_file)), 2L)
})
