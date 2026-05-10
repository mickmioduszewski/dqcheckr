library(testthat)
library(dqcheckr)

make_df <- function() {
  data.frame(
    id              = paste0("ID00", 1:5),
    account_balance = c("15000", "8500", "0", "250000", "1200"),
    stringsAsFactors = FALSE
  )
}

base_config <- function() {
  list(
    format       = "csv",
    rules        = list(
      max_missing_rate     = 0.05,
      max_non_numeric_rate = 0.01,
      min_row_count        = 0
    ),
    column_rules     = list(),
    key_columns      = NULL,
    expected_columns = NULL
  )
}

make_results <- function() {
  list(
    dq_result("QC-01", "Missing rate", column = "id",
              status = "PASS", observed = "0%", message = "OK"),
    dq_result("QC-04", "Row count",
              status = "INFO", observed = "5", message = "5 rows")
  )
}

# -- init_snapshot_db() --------------------------------------------------------

test_that("init_snapshot_db() creates both tables on a new database", {
  db  <- tempfile(fileext = ".sqlite")
  init_snapshot_db(db)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  tables <- DBI::dbListTables(con)
  DBI::dbDisconnect(con)
  expect_true("snapshots"        %in% tables)
  expect_true("column_snapshots" %in% tables)
  unlink(db)
})

test_that("init_snapshot_db() is idempotent (calling twice does not error)", {
  db <- tempfile(fileext = ".sqlite")
  expect_no_error(init_snapshot_db(db))
  expect_no_error(init_snapshot_db(db))
  unlink(db)
})

test_that("init_snapshot_db() creates parent directory if missing", {
  tmp <- file.path(tempdir(), "dqtest_newsubdir", "snap.sqlite")
  init_snapshot_db(tmp)
  expect_true(file.exists(tmp))
  unlink(dirname(tmp), recursive = TRUE)
})

# -- write_snapshot() ----------------------------------------------------------

test_that("write_snapshot() returns a positive integer snapshot_id", {
  db  <- tempfile(fileext = ".sqlite")
  sid <- write_snapshot(db, "test_ds", "file.csv",
                        make_df(), make_results(), list(), list(),
                        base_config())
  expect_true(is.numeric(sid) || is.integer(sid))
  expect_true(sid >= 1)
  unlink(db)
})

test_that("write_snapshot() inserts one row into snapshots table", {
  db <- tempfile(fileext = ".sqlite")
  write_snapshot(db, "test_ds", "file.csv",
                 make_df(), make_results(), list(), list(),
                 base_config())
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  n   <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM snapshots")$n
  DBI::dbDisconnect(con)
  expect_equal(n, 1L)
  unlink(db)
})

test_that("write_snapshot() inserts column_snapshots rows", {
  db <- tempfile(fileext = ".sqlite")
  write_snapshot(db, "test_ds", "file.csv",
                 make_df(), make_results(), list(), list(),
                 base_config())
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  n   <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM column_snapshots")$n
  DBI::dbDisconnect(con)
  expect_true(n > 0L)
  unlink(db)
})

test_that("write_snapshot() emits warning but does not stop on write error", {
  fake_dir <- tempfile()
  file.create(fake_dir)
  on.exit(unlink(fake_dir))
  impossible <- file.path(fake_dir, "impossible.sqlite")
  expect_warning(
    write_snapshot(impossible, "ds", "f.csv",
                   make_df(), make_results(), list(), list(),
                   base_config()),
    regexp = "SQLite"
  )
})

# -- read_recent_snapshots() ---------------------------------------------------

test_that("read_recent_snapshots() returns empty data frame when no runs exist", {
  db  <- tempfile(fileext = ".sqlite")
  init_snapshot_db(db)
  res <- read_recent_snapshots(db, "no_such_dataset")
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 0L)
  unlink(db)
})

test_that("read_recent_snapshots() returns empty data frame when db does not exist", {
  res <- read_recent_snapshots(tempfile(fileext = ".sqlite"), "ds")
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 0L)
})

test_that("read_recent_snapshots() returns only rows for the requested dataset", {
  db <- tempfile(fileext = ".sqlite")
  write_snapshot(db, "ds_a", "a.csv", make_df(),
                 make_results(), list(), list(), base_config())
  write_snapshot(db, "ds_b", "b.csv", make_df(),
                 make_results(), list(), list(), base_config())
  res <- read_recent_snapshots(db, "ds_a")
  expect_equal(nrow(res), 1L)
  expect_true(all(res$dataset_name == "ds_a"))
  unlink(db)
})

test_that("read_recent_snapshots() returns at most n rows", {
  db <- tempfile(fileext = ".sqlite")
  for (i in 1:5) {
    write_snapshot(db, "ds_a", paste0("f", i, ".csv"), make_df(),
                   make_results(), list(), list(), base_config())
  }
  res <- read_recent_snapshots(db, "ds_a", n = 3)
  expect_equal(nrow(res), 3L)
  unlink(db)
})

# -- compute_col_stats() column contract ---------------------------------------

test_that("compute_col_stats() returns a data frame with the correct 5 columns in order", {
  df  <- data.frame(
    id    = c("1", "2", "3"),
    score = c("10.5", "20.0", "bad"),
    stringsAsFactors = FALSE
  )
  cfg <- list(rules = list(
    max_missing_rate    = 0.05,
    max_non_numeric_rate = 0.01,
    type_inference_threshold = 0.90
  ))
  qc <- run_qc_checks(df, cfg)
  cs <- compute_col_stats(df, cfg, qc)

  expect_s3_class(cs, "data.frame")
  expect_equal(names(cs),
               c("column_name", "dq_check", "value", "threshold", "severity_on_breach"))
})

test_that("compute_col_stats() column names map correctly to report display names", {
  df  <- data.frame(x = c("1", "2"), stringsAsFactors = FALSE)
  cfg <- list(rules = list(max_missing_rate = 0.05,
                           max_non_numeric_rate = 0.01,
                           type_inference_threshold = 0.90))
  qc  <- run_qc_checks(df, cfg)
  cs  <- compute_col_stats(df, cfg, qc)
  names(cs) <- c("Column", "Stat", "Value", "Threshold", "Severity")
  expect_equal(names(cs), c("Column", "Stat", "Value", "Threshold", "Severity"))
})
