

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

test_that(".sqlite_connect() sets a busy timeout so a concurrent writer waits (B-09)", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  init_snapshot_db(db)
  con <- dqcheckr:::.sqlite_connect(db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  # Default RSQLite busy_timeout is 0 (fail instantly). We set 30s.
  expect_equal(DBI::dbGetQuery(con, "PRAGMA busy_timeout")[[1]], 30000L)
})

test_that("init_snapshot_db() rejects a foreign 'snapshots' table (S-04)", {
  db  <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  DBI::dbExecute(con, "CREATE TABLE snapshots (foo TEXT, bar INTEGER)")
  DBI::dbExecute(con, "INSERT INTO snapshots VALUES ('a', 1)")
  DBI::dbDisconnect(con)

  expect_error(init_snapshot_db(db), class = "dqcheckr_schema_error")
  # The user's table (and its row) must be left exactly as it was.
  con2 <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con2), add = TRUE)
  expect_identical(
    DBI::dbGetQuery(con2, "SELECT name FROM pragma_table_info('snapshots')")$name,
    c("foo", "bar"))
  expect_equal(DBI::dbGetQuery(con2, "SELECT COUNT(*) AS n FROM snapshots")$n, 1L)
})

test_that("init_snapshot_db() migrates case-insensitively (S-04)", {
  # SQLite column names are case-insensitive; a stored `Report_File` must not be
  # re-added as `report_file` (SQLite would reject it as a duplicate column).
  db  <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  DBI::dbExecute(con, "
    CREATE TABLE snapshots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      dataset_name TEXT NOT NULL, run_timestamp TEXT NOT NULL,
      file_name TEXT NOT NULL, row_count INTEGER NOT NULL,
      col_count INTEGER NOT NULL, overall_status TEXT NOT NULL,
      Report_File TEXT)")
  DBI::dbDisconnect(con)
  expect_no_error(init_snapshot_db(db))
})

test_that("concurrent first-run migrations do not collide (B-10)", {
  skip_on_cran()
  skip_on_os(c("windows", "solaris"))       # relies on fork()
  skip_if_not_installed("parallel")

  # A pre-0.2.3 database still missing all four newer columns.
  db  <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  DBI::dbExecute(con, "
    CREATE TABLE snapshots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      dataset_name TEXT NOT NULL, run_timestamp TEXT NOT NULL,
      file_name TEXT NOT NULL, row_count INTEGER NOT NULL,
      col_count INTEGER NOT NULL, overall_status TEXT NOT NULL)")
  DBI::dbDisconnect(con)

  # Two processes racing init_snapshot_db() on the shared DB. Before the fix one
  # loser dies with 'duplicate column name'; with BEGIN IMMEDIATE both migrate.
  run_one <- function(i) tryCatch({ dqcheckr:::init_snapshot_db(db); "ok" },
                                  error = function(e) conditionMessage(e))
  jobs    <- lapply(1:2, function(i) parallel::mcparallel(run_one(i)))
  results <- parallel::mccollect(jobs)

  expect_true(all(vapply(results, function(r) identical(r, "ok"), logical(1))),
              info = paste(unlist(results), collapse = " | "))

  con2 <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con2), add = TRUE)
  cols <- DBI::dbGetQuery(con2, "SELECT name FROM pragma_table_info('snapshots')")$name
  expect_true(all(c("comparison_mode", "render_status",
                    "type_changed_cols_vs_previous", "report_file") %in% cols))
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
                        make_snapshot_df(), make_results(), list(), list(),
                        base_config())
  expect_true(is.numeric(sid) || is.integer(sid))
  expect_true(sid >= 1)
})

test_that("write_snapshot() inserts one row into snapshots table", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  write_snapshot(db, "test_ds", "file.csv",
                 make_snapshot_df(), make_results(), list(), list(),
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
                 make_snapshot_df(), make_results(), list(), list(),
                 base_config())
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  n <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM column_snapshots")$n
  expect_true(n > 0L)
})

test_that("write_snapshot() stores comparison_mode correctly", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  write_snapshot(db, "ds", "f.csv", make_snapshot_df(), make_results(), list(), list(),
                 base_config(), comparison_mode = "single")
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  mode <- DBI::dbGetQuery(con, "SELECT comparison_mode FROM snapshots")$comparison_mode
  expect_equal(mode, "single")
})

test_that("write_snapshot() stores render_status as 'pending' initially (B-04)", {
  # The row is committed before the report renders; it must read 'pending' in
  # that window, not a premature 'success' that a concurrent reader could mistake
  # for a finished row.
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  write_snapshot(db, "ds", "f.csv", make_snapshot_df(), make_results(), list(), list(),
                 base_config())
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  rs <- DBI::dbGetQuery(con,
    "SELECT render_status, report_file FROM snapshots")
  expect_equal(rs$render_status, "pending")
  expect_true(is.na(rs$report_file))
})

test_that(".set_report_file() flips 'pending' to 'success' and records the filename (B-04)", {
  db  <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  sid <- write_snapshot(db, "ds", "f.csv", make_snapshot_df(), make_results(), list(), list(),
                        base_config())
  dqcheckr:::.set_report_file(db, sid, "ds_20260718_010203_1.html")
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  row <- DBI::dbGetQuery(con, "SELECT render_status, report_file FROM snapshots")
  expect_equal(row$render_status, "success")
  expect_equal(row$report_file, "ds_20260718_010203_1.html")
})

test_that(".mark_render_failed() updates render_status to 'failed'", {
  db  <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  sid <- write_snapshot(db, "ds", "f.csv", make_snapshot_df(), make_results(), list(), list(),
                        base_config())
  dqcheckr:::.mark_render_failed(db, sid)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  rs <- DBI::dbGetQuery(con, "SELECT render_status FROM snapshots")$render_status
  expect_equal(rs, "failed")
})

test_that(".mark_render_failed() clears report_file so no phantom link survives", {
  db  <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  sid <- write_snapshot(db, "ds", "f.csv", make_snapshot_df(), make_results(),
                        list(), list(), base_config(),
                        report_file = "ds_20260101_000000.html")
  dqcheckr:::.mark_render_failed(db, sid)
  snaps <- read_recent_snapshots(db, "ds")
  expect_equal(snaps$render_status[1], "failed")
  expect_true(is.na(snaps$report_file[1]))   # optimistic filename removed
})

test_that("write_snapshot() stores UTC timestamp in ISO-8601 format", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  write_snapshot(db, "ds", "f.csv", make_snapshot_df(), make_results(), list(), list(),
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
                   make_snapshot_df(), make_results(), list(), list(),
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

test_that("read_recent_snapshots() warns instead of silently emptying on a read error (B-16)", {
  # A valid DB whose `snapshots` table cannot satisfy the query (schema mismatch,
  # like a corrupt/foreign file would produce) must not read as 'no history'.
  bad <- tempfile(fileext = ".sqlite")
  on.exit(unlink(bad))
  con <- DBI::dbConnect(RSQLite::SQLite(), bad)
  DBI::dbExecute(con, "CREATE TABLE snapshots (wrong_col TEXT)")
  DBI::dbDisconnect(con)

  expect_warning(res <- read_recent_snapshots(bad, "ds"),
                 regexp = "Could not read snapshot history")
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 0L)
})

test_that("read_recent_snapshots() returns only rows for the requested dataset", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  write_snapshot(db, "ds_a", "a.csv", make_snapshot_df(),
                 make_results(), list(), list(), base_config())
  write_snapshot(db, "ds_b", "b.csv", make_snapshot_df(),
                 make_results(), list(), list(), base_config())
  res <- read_recent_snapshots(db, "ds_a")
  expect_equal(nrow(res), 1L)
  expect_true(all(res$dataset_name == "ds_a"))
})

test_that("read_recent_snapshots() returns at most n rows", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  for (i in 1:5)
    write_snapshot(db, "ds_a", paste0("f", i, ".csv"), make_snapshot_df(),
                   make_results(), list(), list(), base_config())
  res <- read_recent_snapshots(db, "ds_a", n = 3)
  expect_equal(nrow(res), 3L)
})

# -- run_time threading (0.2.3, B-04) --------------------------------------------

test_that("write_snapshot() stores the supplied run_time as run_timestamp", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  rt <- as.POSIXct("2026-07-04 01:02:03", tz = "UTC")
  id <- write_snapshot(db, "ts_ds", "f.csv", make_accounts_df(),
                       make_results(), list(), list(), base_config(),
                       run_time = rt)
  expect_false(is.null(id))
  snaps <- read_recent_snapshots(db, "ts_ds")
  expect_equal(snaps$run_timestamp[1], "2026-07-04T01:02:03Z")
})

# -- Batched column-level custom results (0.2.3, B-06/P-04) -----------------------

test_that("write_snapshot() records column-level custom results", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  custom <- list(
    dq_result("CUST-01", "org rule", column = "id",
              status = "WARN", observed = "5", threshold = "3", message = "m"),
    dq_result("CUST-02", "table rule",                    # no column: not stored
              status = "PASS", observed = "ok", message = "m")
  )
  id <- write_snapshot(db, "cust_ds", "f.csv", make_accounts_df(),
                       make_results(), list(), custom, base_config())
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  rows <- DBI::dbGetQuery(con,
    "SELECT * FROM column_snapshots WHERE dq_check LIKE 'CUST-%' AND snapshot_id = ?",
    list(id))
  expect_equal(nrow(rows), 1)
  expect_equal(rows$column_name, "id")
  expect_equal(rows$severity_on_breach, "WARN")
})

test_that("compute_col_stats() defines missing_rate as 0 for a zero-row frame", {
  stats <- compute_col_stats(make_accounts_df()[0, ], base_config())
  mr <- stats[stats$dq_check == "missing_rate", "value"]
  expect_true(all(mr == "0"))
})

# -- report_file column (0.2.3, B-04 second half) --------------------------------

test_that("write_snapshot() stores report_file and migration adds the column", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  rt <- as.POSIXct("2026-07-04 10:11:12", tz = "UTC")
  write_snapshot(db, "rf_ds", "f.csv", make_accounts_df(),
                 make_results(), list(), list(), base_config(),
                 run_time = rt, report_file = "rf_ds_20260704_101112.html")
  snaps <- read_recent_snapshots(db, "rf_ds")
  expect_equal(snaps$report_file[1], "rf_ds_20260704_101112.html")
})

test_that("report_file is NA when not supplied (pre-0.2.3 writers)", {
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  write_snapshot(db, "rf_na_ds", "f.csv", make_accounts_df(),
                 make_results(), list(), list(), base_config())
  snaps <- read_recent_snapshots(db, "rf_na_ds")
  expect_true(is.na(snaps$report_file[1]))
})

test_that("read_recent_snapshots() empty fallback matches the live schema", {
  empty <- read_recent_snapshots(tempfile(fileext = ".sqlite"), "nope")
  # Same columns whether the DB exists or not
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  write_snapshot(db, "schema_ds", "f.csv", make_accounts_df(),
                 make_results(), list(), list(), base_config())
  live <- read_recent_snapshots(db, "schema_ds")
  expect_setequal(names(empty), names(live))
})

test_that("report_filename() produces the documented slug", {
  rt <- as.POSIXct("2026-07-04 10:11:12", tz = "UTC")
  # id-less form (default) is the pre-0.2.5 pattern.
  expect_equal(report_filename("mydata", rt), "mydata_20260704_101112.html")
  # With a snapshot id, it is appended for uniqueness (B-42).
  expect_equal(report_filename("mydata", rt, 47L), "mydata_20260704_101112_47.html")
})

# -- read_recent_snapshots() backfill on un-migrated databases (B-01) ------------
# The tests above all reach the DB through write_snapshot(), which calls
# init_snapshot_db() and migrates first, so a read against a genuinely old,
# never-written database is never exercised there. These build the old schema by
# hand and INSERT directly, so the row is read back WITHOUT any ALTER.

test_that("read_recent_snapshots() backfills columns absent from a 0.1.x database", {
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
  DBI::dbExecute(con,
    "INSERT INTO snapshots
       (dataset_name, run_timestamp, file_name, row_count, col_count, overall_status)
     VALUES ('old_ds', '2025-01-01T00:00:00Z', 'f.csv', 10, 3, 'PASS')")
  DBI::dbDisconnect(con)

  # A read must not have mutated the file on disk (read-only shares).
  con2 <- DBI::dbConnect(RSQLite::SQLite(), db)
  before <- DBI::dbGetQuery(con2, "SELECT name FROM pragma_table_info('snapshots')")$name
  DBI::dbDisconnect(con2)

  res <- read_recent_snapshots(db, "old_ds")

  con3 <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con3), add = TRUE)
  after <- DBI::dbGetQuery(con3, "SELECT name FROM pragma_table_info('snapshots')")$name
  expect_setequal(before, after)  # read did NOT ALTER the table

  # Frame carries the full 0.2.3 schema, in schema order.
  proto <- read_recent_snapshots(tempfile(fileext = ".sqlite"), "nope")
  expect_equal(names(res), names(proto))
  expect_equal(nrow(res), 1L)

  # Backfilled values match what ALTER TABLE ... DEFAULT would have written.
  expect_equal(res$comparison_mode, "comparison")
  expect_equal(res$render_status, "success")
  expect_true(is.na(res$report_file))
  expect_true(is.na(res$type_changed_cols_vs_previous))
  expect_true(is.na(res$check_pass_count))
  # Real columns survive untouched.
  expect_equal(res$dataset_name, "old_ds")
  expect_equal(res$row_count, 10L)
})

test_that("read_recent_snapshots() backfills report_file on a 0.2.2 database", {
  # 0.2.2 (current CRAN) has every column except report_file: 18 vs 19.
  db <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  DBI::dbExecute(con, "
    CREATE TABLE snapshots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      dataset_name TEXT NOT NULL, run_timestamp TEXT NOT NULL,
      file_name TEXT NOT NULL, row_count INTEGER NOT NULL, col_count INTEGER NOT NULL,
      check_pass_count INTEGER, check_warn_count INTEGER, check_fail_count INTEGER,
      check_info_count INTEGER, overall_status TEXT NOT NULL,
      new_cols_vs_previous TEXT, missing_cols_vs_previous TEXT,
      new_cols_vs_schema TEXT, missing_cols_vs_schema TEXT,
      comparison_mode TEXT NOT NULL DEFAULT 'comparison',
      render_status TEXT NOT NULL DEFAULT 'success',
      type_changed_cols_vs_previous TEXT
    )")
  DBI::dbExecute(con,
    "INSERT INTO snapshots
       (dataset_name, run_timestamp, file_name, row_count, col_count, overall_status)
     VALUES ('v022_ds', '2026-01-01T00:00:00Z', 'f.csv', 7, 2, 'WARN')")
  DBI::dbDisconnect(con)

  res <- read_recent_snapshots(db, "v022_ds")
  proto <- read_recent_snapshots(tempfile(fileext = ".sqlite"), "nope")
  expect_equal(names(res), names(proto))
  expect_true("report_file" %in% names(res))
  expect_true(is.na(res$report_file))
  expect_equal(res$comparison_mode, "comparison")  # real stored value, still correct
})

test_that("read_recent_snapshots() backfill keeps a zero-row result correctly typed", {
  # No matching dataset in an un-migrated DB: the SELECT returns zero rows but
  # still only the old columns. The backfill must add the rest without erroring.
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
  DBI::dbDisconnect(con)

  res <- read_recent_snapshots(db, "absent_ds")
  proto <- read_recent_snapshots(tempfile(fileext = ".sqlite"), "nope")
  expect_equal(names(res), names(proto))
  expect_equal(nrow(res), 0L)
})
