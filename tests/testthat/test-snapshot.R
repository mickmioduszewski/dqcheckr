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
    column_types     = list(),
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
  on.exit(unlink(db))
  init_snapshot_db(db)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  tables <- DBI::dbListTables(con)
  expect_true("snapshots"        %in% tables)
  expect_true("column_snapshots" %in% tables)
})

test_that("init_snapshot_db() is idempotent (calling twice does not error)", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  expect_no_error(init_snapshot_db(db))
  expect_no_error(init_snapshot_db(db))
})

test_that("init_snapshot_db() creates parent directory if missing", {
  tmp <- file.path(tempdir(), paste0("dqtest_newsubdir_", Sys.getpid()), "snap.sqlite")
  on.exit(unlink(dirname(tmp), recursive = TRUE))
  init_snapshot_db(tmp)
  expect_true(file.exists(tmp))
})

test_that("init_snapshot_db() creates new columns (comparison_mode, render_status, type_changed_cols_vs_previous)", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  init_snapshot_db(db)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  cols <- DBI::dbGetQuery(con, "SELECT name FROM pragma_table_info('snapshots')")$name
  expect_true("comparison_mode"               %in% cols)
  expect_true("render_status"                 %in% cols)
  expect_true("type_changed_cols_vs_previous" %in% cols)
})

test_that("init_snapshot_db() auto-migrates a 0.1.x database missing new columns", {
  # Build a bare 0.1.x schema manually
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  DBI::dbExecute(con, "
    CREATE TABLE snapshots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      dataset_name TEXT NOT NULL, run_timestamp TEXT NOT NULL,
      file_name TEXT NOT NULL, row_count INTEGER NOT NULL,
      col_count INTEGER NOT NULL, overall_status TEXT NOT NULL
    )")
  DBI::dbExecute(con, "
    CREATE TABLE column_snapshots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      snapshot_id INTEGER NOT NULL, column_name TEXT NOT NULL,
      dq_check TEXT NOT NULL, value TEXT, threshold TEXT, severity_on_breach TEXT
    )")
  DBI::dbDisconnect(con)

  # init_snapshot_db should add the missing columns without error
  expect_no_error(init_snapshot_db(db))

  con2 <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con2), add = TRUE)
  cols <- DBI::dbGetQuery(con2, "SELECT name FROM pragma_table_info('snapshots')")$name
  expect_true("comparison_mode"               %in% cols)
  expect_true("render_status"                 %in% cols)
  expect_true("type_changed_cols_vs_previous" %in% cols)
})

test_that("FK enforcement is active on connections opened by .sqlite_connect", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  init_snapshot_db(db)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  fk_on <- DBI::dbGetQuery(con, "PRAGMA foreign_keys")[[1]]
  # Default RSQLite = 0; .sqlite_connect sets it to 1
  # We test init_snapshot_db opened with .sqlite_connect:
  con2 <- dqcheckr:::.sqlite_connect(db)
  on.exit(DBI::dbDisconnect(con2), add = TRUE)
  expect_equal(DBI::dbGetQuery(con2, "PRAGMA foreign_keys")[[1]], 1L)
})

# -- write_snapshot() ----------------------------------------------------------

test_that("write_snapshot() returns a positive integer snapshot_id", {
  db  <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  sid <- write_snapshot(db, "test_ds", "file.csv",
                        make_df(), make_results(), list(), list(),
                        base_config())
  expect_true(is.numeric(sid) || is.integer(sid))
  expect_true(sid >= 1)
})

test_that("write_snapshot() inserts one row into snapshots table", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  write_snapshot(db, "test_ds", "file.csv",
                 make_df(), make_results(), list(), list(),
                 base_config())
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  n <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM snapshots")$n
  expect_equal(n, 1L)
})

test_that("write_snapshot() inserts column_snapshots rows", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  write_snapshot(db, "test_ds", "file.csv",
                 make_df(), make_results(), list(), list(),
                 base_config())
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  n <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM column_snapshots")$n
  expect_true(n > 0L)
})

test_that("write_snapshot() stores comparison_mode correctly", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  write_snapshot(db, "ds", "f.csv", make_df(), make_results(), list(), list(),
                 base_config(), comparison_mode = "single")
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  mode <- DBI::dbGetQuery(con, "SELECT comparison_mode FROM snapshots")$comparison_mode
  expect_equal(mode, "single")
})

test_that("write_snapshot() stores render_status as 'success' initially", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  write_snapshot(db, "ds", "f.csv", make_df(), make_results(), list(), list(),
                 base_config())
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  rs <- DBI::dbGetQuery(con, "SELECT render_status FROM snapshots")$render_status
  expect_equal(rs, "success")
})

test_that(".mark_render_failed() updates render_status to 'failed'", {
  db  <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  sid <- write_snapshot(db, "ds", "f.csv", make_df(), make_results(), list(), list(),
                        base_config())
  dqcheckr:::.mark_render_failed(db, sid)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  rs <- DBI::dbGetQuery(con, "SELECT render_status FROM snapshots")$render_status
  expect_equal(rs, "failed")
})

test_that("write_snapshot() stores UTC timestamp in ISO-8601 format", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  write_snapshot(db, "ds", "f.csv", make_df(), make_results(), list(), list(),
                 base_config())
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  ts <- DBI::dbGetQuery(con, "SELECT run_timestamp FROM snapshots")$run_timestamp
  expect_match(ts, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
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

# -- compute_col_stats() -------------------------------------------------------

test_that("compute_col_stats() returns a data frame with the correct 5 columns", {
  df  <- data.frame(
    id    = c("1", "2", "3"),
    score = c("10.5", "20.0", "bad"),
    stringsAsFactors = FALSE
  )
  cfg <- list(rules = list(
    max_missing_rate         = 0.05,
    max_non_numeric_rate     = 0.01,
    type_inference_threshold = 0.90
  ), column_rules = list(), column_types = list())
  cs <- compute_col_stats(df, cfg)
  expect_s3_class(cs, "data.frame")
  expect_equal(names(cs),
               c("column_name", "dq_check", "value", "threshold", "severity_on_breach"))
})

test_that("compute_col_stats() uses 'numeric_parseable_mean' as the stat key", {
  df  <- data.frame(x = c("1", "2", "3"), stringsAsFactors = FALSE)
  cfg <- list(rules = list(max_missing_rate = 0.05, max_non_numeric_rate = 0.01,
                           type_inference_threshold = 0.90),
              column_rules = list(), column_types = list())
  cs  <- compute_col_stats(df, cfg)
  expect_true("numeric_parseable_mean" %in% cs$dq_check)
  expect_false("numeric_mean" %in% cs$dq_check)
})

test_that("compute_col_stats() stores per-column threshold via col_threshold()", {
  df  <- data.frame(x = c("1", "2", NA), stringsAsFactors = FALSE)
  cfg <- list(
    rules        = list(max_missing_rate = 0.05, max_non_numeric_rate = 0.01,
                        type_inference_threshold = 0.90),
    column_rules = list(x = list(max_missing_rate = 0.50)),
    column_types = list()
  )
  cs <- compute_col_stats(df, cfg)
  mr_row <- cs[cs$column_name == "x" & cs$dq_check == "missing_rate", ]
  expect_equal(as.numeric(mr_row$threshold), 0.50)
})

# -- read_recent_snapshots() ---------------------------------------------------

test_that("read_recent_snapshots() returns empty data frame when no runs exist", {
  db  <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  init_snapshot_db(db)
  res <- read_recent_snapshots(db, "no_such_dataset")
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 0L)
})

test_that("read_recent_snapshots() returns empty data frame when db does not exist", {
  res <- read_recent_snapshots(tempfile(fileext = ".sqlite"), "ds")
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 0L)
})

test_that("read_recent_snapshots() returns only rows for the requested dataset", {
  db <- tempfile(fileext = ".sqlite")
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
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  for (i in 1:5)
    write_snapshot(db, "ds_a", paste0("f", i, ".csv"), make_df(),
                   make_results(), list(), list(), base_config())
  res <- read_recent_snapshots(db, "ds_a", n = 3)
  expect_equal(nrow(res), 3L)
})
