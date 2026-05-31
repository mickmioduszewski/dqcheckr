library(testthat)
library(dqcheckr)

# Helper: call render_report() with a minimal in-memory dataset
run_minimal_render <- function() {
  tmp <- tempdir()
  df  <- data.frame(id = c("1", "2"), val = c("10", "20"),
                    stringsAsFactors = FALSE)
  cfg <- list(
    format       = "csv",
    rules        = list(max_missing_rate = 0.05, max_non_numeric_rate = 0.01,
                        min_row_count = 0),
    column_rules = list(), key_columns = NULL, expected_columns = NULL
  )
  qc <- run_qc_checks(df, cfg)
  cs <- compute_col_stats(df, cfg, qc)
  render_report(
    dataset_name     = "tmpds",
    file_name        = "tmp.csv",
    file_path        = file.path(tmp, "tmp.csv"),
    df               = df,
    qc_results       = qc,
    cp_results       = list(),
    custom_results   = list(),
    snapshot_history = data.frame(),
    config           = cfg,
    col_stats        = cs,
    output_dir       = tmp,
    open_report      = FALSE
  )
}

# T-01: template directory file list is unchanged after a render
test_that("render_report() leaves no new files in the template directory", {
  skip_if_not(rmarkdown::pandoc_available())
  tmpl_dir <- system.file("templates", package = "dqcheckr")
  before   <- sort(list.files(tmpl_dir, all.files = TRUE))
  run_minimal_render()
  after    <- sort(list.files(tmpl_dir, all.files = TRUE))
  expect_equal(after, before)
})

# T-02: no intermediate files are written into the template directory
test_that("render_report() writes intermediate files only under tempdir()", {
  skip_if_not(rmarkdown::pandoc_available())
  tmpl_dir   <- system.file("templates", package = "dqcheckr")
  before     <- normalizePath(
    list.files(tmpl_dir, full.names = TRUE, all.files = TRUE))
  run_minimal_render()
  after      <- normalizePath(
    list.files(tmpl_dir, full.names = TRUE, all.files = TRUE))
  new_in_tmpl <- setdiff(after, before)
  expect_length(new_in_tmpl, 0L)
})

# T-03: compare_snapshots(report = TRUE) leaves template directory unchanged
test_that("compare_snapshots(report=TRUE) leaves no new files in template directory", {
  skip_if_not(rmarkdown::pandoc_available())
  db       <- make_drift_db(2)
  cfg_dir  <- make_drift_config()
  tmpl_dir <- system.file("templates", package = "dqcheckr")
  before   <- sort(list.files(tmpl_dir, all.files = TRUE))
  compare_snapshots("test_ds", db_path = db, config_dir = cfg_dir,
                    report = TRUE, open_report = FALSE)
  after    <- sort(list.files(tmpl_dir, all.files = TRUE))
  expect_equal(after, before)
})
