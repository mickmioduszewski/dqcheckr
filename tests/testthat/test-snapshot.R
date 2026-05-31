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

duck_con <- function(db) DBI::dbConnect(duckdb::duckdb(), db)

# -- init_snapshot_db() --------------------------------------------------------

test_that("init_snapshot_db() creates both tables on a new database", {
  db  <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db))
  init_snapshot_db(db)
  con <- duck_con(db)
  tables <- DBI::dbListTables(con)
  DBI::dbDisconnect(con)
  expect_true("snapshots"        %in% tables)
  expect_true("column_snapshots" %in% tables)
})

test_that("init_snapshot_db() is idempotent (calling twice does not error)", {
  db <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db))
  expect_no_error(init_snapshot_db(db))
  expect_no_error(init_snapshot_db(db))
})

test_that("init_snapshot_db() creates parent directory if missing", {
  tmp <- file.path(tempdir(), "dqtest_newsubdir", "snap.duckdb")
  on.exit(unlink(dirname(tmp), recursive = TRUE))
  init_snapshot_db(tmp)
  expect_true(file.exists(tmp))
})

# -- write_snapshot() ----------------------------------------------------------

test_that("write_snapshot() returns a positive integer snapshot_id", {
  db  <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db))
  sid <- write_snapshot(db, "test_ds", "file.csv",
                        make_df(), make_results(), list(), list(),
                        base_config())
  expect_true(is.numeric(sid) || is.integer(sid))
  expect_true(sid >= 1)
})

test_that("write_snapshot() inserts one row into snapshots table", {
  db <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db))
  write_snapshot(db, "test_ds", "file.csv",
                 make_df(), make_results(), list(), list(),
                 base_config())
  con <- duck_con(db)
  n   <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM snapshots")$n
  DBI::dbDisconnect(con)
  expect_equal(n, 1L)
})

test_that("write_snapshot() inserts column_snapshots rows", {
  db <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db))
  write_snapshot(db, "test_ds", "file.csv",
                 make_df(), make_results(), list(), list(),
                 base_config())
  con <- duck_con(db)
  n   <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM column_snapshots")$n
  DBI::dbDisconnect(con)
  expect_true(n > 0L)
})

test_that("write_snapshot() returns NULL and does not stop on write error", {
  fake_dir <- tempfile()
  file.create(fake_dir)
  on.exit(unlink(fake_dir))
  impossible <- file.path(fake_dir, "impossible.duckdb")
  result <- suppressWarnings(
    write_snapshot(impossible, "ds", "f.csv",
                   make_df(), make_results(), list(), list(),
                   base_config())
  )
  expect_null(result)
})

test_that("write_snapshot() stores run_timestamp in UTC ISO format", {
  db  <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db))
  write_snapshot(db, "test_ds", "file.csv",
                 make_df(), make_results(), list(), list(),
                 base_config())
  con <- duck_con(db)
  ts  <- DBI::dbGetQuery(con,
    "SELECT run_timestamp FROM snapshots")$run_timestamp
  DBI::dbDisconnect(con)
  expect_match(ts, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
})

test_that("render_status defaults to 'success' in new snapshots", {
  db  <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db))
  sid <- write_snapshot(db, "test_ds", "file.csv",
                        make_df(), make_results(), list(), list(),
                        base_config())
  con <- duck_con(db)
  rs  <- DBI::dbGetQuery(con,
    "SELECT render_status FROM snapshots WHERE id = ?",
    list(sid))$render_status
  DBI::dbDisconnect(con)
  expect_equal(rs, "success")
})

test_that("write_snapshot() stores comparison_mode = 'single' in single-file mode", {
  db  <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db))
  write_snapshot(db, "ds", "f.csv", make_df(),
                 make_results(), list(), list(), base_config())
  con  <- duck_con(db)
  mode <- DBI::dbGetQuery(con,
    "SELECT comparison_mode FROM snapshots")$comparison_mode
  DBI::dbDisconnect(con)
  expect_equal(mode, "single")
})

# -- read_recent_snapshots() ---------------------------------------------------

test_that("read_recent_snapshots() returns empty data frame when no runs exist", {
  db  <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db))
  init_snapshot_db(db)
  res <- read_recent_snapshots(db, "no_such_dataset")
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 0L)
})

test_that("read_recent_snapshots() returns empty data frame when db does not exist", {
  res <- read_recent_snapshots(tempfile(fileext = ".duckdb"), "ds")
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 0L)
})

test_that("read_recent_snapshots() returns only rows for the requested dataset", {
  db <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db))
  write_snapshot(db, "ds_a", "a.csv", make_df(),
                 make_results(), list(), list(), base_config())
  write_snapshot(db, "ds_b", "b.csv", make_df(),
                 make_results(), list(), list(), base_config())
  res <- read_recent_snapshots(db, "ds_a")
  expect_equal(nrow(res), 1L)
  expect_true(all(res$dataset_name == "ds_a"))
})

test_that("read_recent_snapshots() returns at most n rows", {
  db <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db))
  for (i in 1:5) {
    write_snapshot(db, "ds_a", paste0("f", i, ".csv"), make_df(),
                   make_results(), list(), list(), base_config())
  }
  res <- read_recent_snapshots(db, "ds_a", n = 3)
  expect_equal(nrow(res), 3L)
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
  cs <- compute_col_stats(df, cfg)

  expect_s3_class(cs, "data.frame")
  expect_equal(names(cs),
               c("column_name", "dq_check", "value", "threshold", "severity_on_breach"))
})

test_that("compute_col_stats() column names map correctly to report display names", {
  df  <- data.frame(x = c("1", "2"), stringsAsFactors = FALSE)
  cfg <- list(rules = list(max_missing_rate = 0.05,
                           max_non_numeric_rate = 0.01,
                           type_inference_threshold = 0.90))
  cs  <- compute_col_stats(df, cfg)
  names(cs) <- c("Column", "Stat", "Value", "Threshold", "Severity")
  expect_equal(names(cs), c("Column", "Stat", "Value", "Threshold", "Severity"))
})

test_that("compute_col_stats() uses numeric_parseable_mean label for numeric columns", {
  df  <- data.frame(val = c("1", "2", "3"), stringsAsFactors = FALSE)
  cfg <- list(rules = list(max_missing_rate = 0.05,
                           max_non_numeric_rate = 0.01,
                           type_inference_threshold = 0.90))
  cs  <- compute_col_stats(df, cfg)
  expect_true("numeric_parseable_mean" %in% cs$dq_check)
  expect_false("numeric_mean"           %in% cs$dq_check)
})

test_that("write_snapshot() stores type_changed_cols_vs_previous from CP-02c", {
  db  <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db))
  curr <- data.frame(val = c("1","2","3"), stringsAsFactors = FALSE)
  prev <- data.frame(val = c("a","b","c"), stringsAsFactors = FALSE)
  cfg  <- list(rules = list(max_missing_rate=0.05, max_non_numeric_rate=0.01),
               column_rules=list(), key_columns=NULL, expected_columns=NULL,
               format="csv")
  qc <- run_qc_checks(curr, cfg)
  cp <- run_comparison_checks(curr, prev, cfg)
  sid <- write_snapshot(db, "ds", "f.csv", curr, qc, cp, list(), cfg)
  con <- duck_con(db)
  tc  <- DBI::dbGetQuery(con,
    "SELECT type_changed_cols_vs_previous FROM snapshots WHERE id = ?",
    list(sid))$type_changed_cols_vs_previous
  DBI::dbDisconnect(con)
  expect_false(is.na(tc))
  expect_match(tc, "val")
})

test_that("compute_col_stats() routes missing_rate threshold via col_threshold (G-01)", {
  cfg <- list(
    rules        = list(max_missing_rate = 0.05, type_inference_threshold = 0.90),
    column_rules = list(account_balance = list(max_missing_rate = 0.00)),
    column_types = list()
  )
  df  <- data.frame(account_balance = c("100", NA_character_), stringsAsFactors = FALSE)
  cs  <- compute_col_stats(df, cfg)
  row <- cs[cs$column_name == "account_balance" & cs$dq_check == "missing_rate", ]
  expect_equal(row$threshold, "0")
})
