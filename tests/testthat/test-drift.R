
test_that("list_snapshots() requires an explicit db_path (B-32)", {
  expect_error(list_snapshots("test_ds"), class = "dqcheckr_invalid_argument")
})

# -- utc_to_local_display() / drift timestamp (B-43) ---------------------------

test_that("utc_to_local_display() converts stored UTC-ISO to local time (B-43)", {
  withr::local_envvar(TZ = "Etc/GMT-10")     # fixed UTC+10, no DST
  expect_equal(dqcheckr:::utc_to_local_display("2026-07-17T10:11:12Z"),
               "2026-07-17 20:11:12")
  # A value that does not parse is returned unchanged, never as NA.
  expect_equal(dqcheckr:::utc_to_local_display("not-a-timestamp"), "not-a-timestamp")
})

test_that("compare_snapshots() carries a local-time timestamp for the drift report (B-43)", {
  withr::local_envvar(TZ = "Etc/GMT-10")
  db      <- make_drift_db(2)                # timestamps stored as ...T09:00:00Z
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)
  expect_equal(drift$snap_prev$run_timestamp_local, "2025-01-01 19:00:00")
  # The raw UTC field is still present but is not what the template renders.
  expect_match(drift$snap_prev$run_timestamp, "Z$")
})

# -- list_snapshots() ----------------------------------------------------------

test_that("list_snapshots() warns instead of silently emptying on a read error (B-07)", {
  # Valid DB, but the `snapshots` table cannot satisfy the query -- must surface
  # the failure, not report it as an empty history.
  bad <- tempfile(fileext = ".sqlite")
  on.exit(unlink(bad))
  con <- DBI::dbConnect(RSQLite::SQLite(), bad)
  DBI::dbExecute(con, "CREATE TABLE snapshots (wrong_col TEXT)")
  DBI::dbDisconnect(con)

  expect_warning(res <- list_snapshots("ds", db_path = bad),
                 regexp = "Could not read snapshots")
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 0L)
})

test_that("list_snapshots returns empty df for non-existent db", {
  result <- list_snapshots(db_path = tempfile(fileext = ".sqlite"))
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0L)
})

test_that("list_snapshots returns empty df for db with no matching dataset", {
  db     <- make_drift_db(2)
  result <- list_snapshots("no_such_dataset", db_path = db)
  expect_equal(nrow(result), 0L)
})

test_that("list_snapshots returns correct columns", {
  db     <- make_drift_db(2)
  result <- list_snapshots("test_ds", db_path = db)
  expect_true(all(c("id", "dataset_name", "file_name",
                    "run_timestamp", "row_count", "overall_status")
                  %in% names(result)))
})

test_that("list_snapshots with NULL returns all datasets", {
  db     <- make_drift_db(2)
  result <- list_snapshots(NULL, db_path = db)
  expect_equal(nrow(result), 2L)
})

test_that("list_snapshots filters by dataset name", {
  db     <- make_drift_db(3)
  result <- list_snapshots("test_ds", db_path = db)
  expect_equal(nrow(result), 3L)
  expect_true(all(result$dataset_name == "test_ds"))
})

# -- compare_snapshots() errors ------------------------------------------------

test_that("compare_snapshots errors if db does not exist", {
  cfg_dir <- make_drift_config()
  expect_error(
    compare_snapshots("x", db_path = tempfile(fileext = ".sqlite"),
                      config_dir = cfg_dir, report = FALSE),
    "not found"
  )
})

test_that("compare_snapshots errors if fewer than 2 snapshots", {
  db      <- make_drift_db(1)
  cfg_dir <- make_drift_config()
  expect_error(
    compare_snapshots("test_ds", db_path = db,
                      config_dir = cfg_dir, report = FALSE),
    "at least 2"
  )
})

test_that("compare_snapshots errors if same ID passed twice", {
  db      <- make_drift_db(2)
  cfg_dir <- make_drift_config()
  expect_error(
    compare_snapshots("test_ds", snapshot_id_prev = 1L, snapshot_id_curr = 1L,
                      db_path = db, config_dir = cfg_dir, report = FALSE),
    "must differ"
  )
})

test_that("compare_snapshots() errors when prev ID is greater than curr ID", {
  db      <- make_drift_db(2)
  cfg_dir <- make_drift_config()
  # Assert the specific ordering-guard class, not the umbrella dqcheckr_error
  # that three earlier abort sites on this call path also carry (B-49).
  expect_error(
    compare_snapshots("test_ds", snapshot_id_prev = 2L, snapshot_id_curr = 1L,
                      db_path = db, config_dir = cfg_dir, report = FALSE),
    class = "dqcheckr_invalid_argument", regexp = "older than"
  )
})

test_that("compare_snapshots() rejects a non-numeric snapshot ID (B-21)", {
  db      <- make_drift_db(2)
  cfg_dir <- make_drift_config()
  # A character ID would sort as a string ("10" > "9" is FALSE) past the
  # ordering guard and then abort untyped inside sprintf("%d", .).
  expect_error(
    compare_snapshots("test_ds", snapshot_id_prev = "10", snapshot_id_curr = "9",
                      db_path = db, config_dir = cfg_dir, report = FALSE),
    class = "dqcheckr_invalid_argument"
  )
  expect_error(
    compare_snapshots("test_ds", snapshot_id_prev = 1.5, snapshot_id_curr = 2L,
                      db_path = db, config_dir = cfg_dir, report = FALSE),
    class = "dqcheckr_invalid_argument"
  )
})

test_that("compare_snapshots() raises a typed error for a bad database (B-30)", {
  cfg_dir <- make_drift_config()

  non_db <- tempfile(fileext = ".sqlite")
  writeLines("this is not a database", non_db)
  # RSQLite emits a "couldn't set synchronous mode" warning at connect for a
  # non-database file; the point of the test is the typed error, not that noise.
  suppressWarnings(expect_error(
    compare_snapshots("test_ds", db_path = non_db,
                      config_dir = cfg_dir, report = FALSE),
    class = "dqcheckr_db_error"
  ))

  no_table <- tempfile(fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), no_table)
  DBI::dbExecute(con, "CREATE TABLE other (x TEXT)")
  DBI::dbDisconnect(con)
  expect_error(
    compare_snapshots("test_ds", db_path = no_table,
                      config_dir = cfg_dir, report = FALSE),
    class = "dqcheckr_schema_error"
  )
})

test_that("drift between two zero-row snapshots renders no NA in Exceeds (B-44/B-47)", {
  db      <- make_drift_db(2)
  cfg_dir <- make_drift_config()
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  DBI::dbExecute(con, "UPDATE snapshots SET row_count = 0")   # two empty deliveries
  DBI::dbDisconnect(con)

  drift <- compare_snapshots("test_ds", db_path = db,
                             config_dir = cfg_dir, report = FALSE)
  row_row <- drift$table_drift[drift$table_drift$Metric == "Row count", ]
  expect_equal(row_row$Exceeds, "")          # 0 -> 0 is no change, not NA
  expect_false(is.na(row_row$Exceeds))
})

# -- drift report render + filename (B-02 / B-03) ------------------------------

test_that(".write_drift_html_report() errors when Quarto writes no file (B-02)", {
  # Quarto 'available' but its render leaves no output file -- the exact case
  # report.R guards. The drift writer must raise, not return a phantom path.
  testthat::local_mocked_bindings(
    quarto_available = function(...) TRUE,
    quarto_render    = function(...) invisible(NULL),
    .package = "quarto")
  out <- file.path(withr::local_tempdir(), "drift_x.html")
  expect_error(
    dqcheckr:::.write_drift_html_report(list(dataset_name = "x"), out),
    class = "dqcheckr_render_error")
})

test_that("compare_snapshots() downgrades a drift render failure and still returns the drift (B-02)", {
  db      <- make_drift_db(2)
  cfg_dir <- make_drift_config()
  testthat::local_mocked_bindings(
    quarto_available = function(...) TRUE,
    quarto_render    = function(...) invisible(NULL),   # renders nothing
    .package = "quarto")
  expect_warning(
    drift <- compare_snapshots("test_ds", db_path = db, config_dir = cfg_dir,
                               report = TRUE, open_report = FALSE),
    regexp = "no output file")
  # The computed drift is the primary result and survives the render failure.
  expect_type(drift, "list")
  expect_true("table_drift" %in% names(drift))
})

test_that("drift filenames carry both snapshot ids and don't collide same-second (B-03)", {
  db      <- make_drift_db(3)
  out_dir <- withr::local_tempdir()
  cfg_dir <- make_drift_config(out_dir)     # report_output_dir = out_dir

  fixed <- as.POSIXct("2026-07-18 01:02:03", tz = "UTC")
  testthat::local_mocked_bindings(
    quarto_available = function(...) TRUE,
    # Write the expected output file so the render 'succeeds' deterministically.
    quarto_render = function(input, output_file, ...)
      writeLines("<html>drift</html>", file.path(dirname(input), output_file)),
    .package = "quarto")
  testthat::local_mocked_bindings(Sys.time = function() fixed, .package = "base")

  compare_snapshots("test_ds", snapshot_id_prev = 1, snapshot_id_curr = 2,
                    db_path = db, config_dir = cfg_dir, report = TRUE, open_report = FALSE)
  compare_snapshots("test_ds", snapshot_id_prev = 1, snapshot_id_curr = 3,
                    db_path = db, config_dir = cfg_dir, report = TRUE, open_report = FALSE)

  files <- list.files(out_dir, pattern = "^drift_test_ds_.*\\.html$")
  expect_length(files, 2)                    # neither overwrote the other
  expect_true(any(grepl("_1_2\\.html$", files)))
  expect_true(any(grepl("_1_3\\.html$", files)))
})

# -- compare_snapshots() default ID selection ----------------------------------

test_that("compare_snapshots defaults to second-latest vs latest", {
  db      <- make_drift_db(3)
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)
  expect_equal(drift$snap_prev$id, 2L)
  expect_equal(drift$snap_curr$id, 3L)
})

test_that("compare_snapshots respects explicit IDs", {
  db      <- make_drift_db(3)
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds",
                               snapshot_id_prev = 1L, snapshot_id_curr = 3L,
                               db_path = db, config_dir = cfg_dir, report = FALSE)
  expect_equal(drift$snap_prev$id, 1L)
  expect_equal(drift$snap_curr$id, 3L)
})

# -- drift list structure ------------------------------------------------------

test_that("compare_snapshots returns list with expected elements", {
  db      <- make_drift_db(2)
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)
  expect_named(drift, c("dataset_name", "snap_prev", "snap_curr",
                        "table_drift", "schema_changes",
                        "missing_rate_changes", "non_numeric_changes",
                        "mean_shifts", "distinct_changes"),
               ignore.order = TRUE)
})

# -- compute_drift: table-level ------------------------------------------------

test_that("table_drift row count change is correct", {
  db      <- make_drift_db(2)
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)
  td      <- drift$table_drift
  row_row <- td[td$Metric == "Row count", ]
  expect_equal(row_row$Previous, 1000L)
  expect_equal(row_row$Current,  2000L)
  expect_equal(row_row$Change,   1000L)
  expect_equal(row_row$Exceeds, "***")  # 100% increase > 10% threshold
})

# -- compute_drift: schema drift -----------------------------------------------

test_that("schema_changes detects new column across snapshots", {
  db  <- make_drift_db(2)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  DBI::dbExecute(con,
    "INSERT INTO column_snapshots
     (snapshot_id, column_name, dq_check, value, threshold, severity_on_breach)
     VALUES (2, 'new_col', 'inferred_type', 'character', NULL, NULL)")
  DBI::dbDisconnect(con)

  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)
  expect_true("new_col" %in% drift$schema_changes$Column)
  expect_equal(
    drift$schema_changes$Status[drift$schema_changes$Column == "new_col"],
    "NEW COLUMN"
  )
})

test_that("schema_changes detects type change", {
  db  <- make_drift_db(2)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  DBI::dbExecute(con,
    "UPDATE column_snapshots
     SET value = 'character'
     WHERE snapshot_id = 2 AND column_name = 'amount'
       AND dq_check = 'inferred_type'")
  DBI::dbDisconnect(con)

  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)
  changed <- drift$schema_changes[drift$schema_changes$Column == "amount", ]
  expect_equal(changed$Status, "TYPE CHANGED")
})

# -- compute_drift: per-column -------------------------------------------------

test_that("missing_rate_changes is filtered to changed columns only", {
  db      <- make_drift_db(2)
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)
  expect_false("status" %in% drift$missing_rate_changes$Column)
})

test_that("missing_rate_changes sorted by magnitude descending", {
  db      <- make_drift_db(3)  # 3 snapshots gives more meaningful changes
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)
  mr <- drift$missing_rate_changes
  expect_s3_class(mr, "data.frame")
  if (nrow(mr) > 1)
    expect_true(all(diff(abs(mr$missing_rate_change_pp)) <= 0))
})

test_that("mean_shifts uses numeric_parseable_mean key", {
  db      <- make_drift_db(2)
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)
  ms <- drift$mean_shifts[drift$mean_shifts$Column == "amount", ]
  expect_equal(ms$numeric_mean_prev, 100)
  expect_equal(ms$numeric_mean_curr, 200)
  expect_equal(ms$numeric_mean_shift_pct, 1.0)
  expect_true(ms$numeric_mean_exceeds)
})

test_that("distinct_changes filtered to changed columns only", {
  db      <- make_drift_db(2)
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)
  expect_false("status" %in% drift$distinct_changes$Column)
})

# -- B-44: drift breach direction matches the CP-03/CP-07 checks ---------------
# Only an *increase* in missing rate (CP-03) or non-numeric rate (CP-07) is a
# breach; a column that improved must not be flagged. Before the fix drift used
# abs(), so a large decrease -- an improvement -- read as "Exceeds YES" while
# the run report passed the same column against the same threshold.

# Two snapshots for one numeric column, with caller-supplied rates.
make_rate_drift_db <- function(mr_prev, mr_curr, nn_prev, nn_curr) {
  db  <- tempfile(fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  on.exit(DBI::dbDisconnect(con))
  DBI::dbExecute(con, "
    CREATE TABLE snapshots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      dataset_name TEXT, run_timestamp TEXT, file_name TEXT,
      row_count INTEGER, col_count INTEGER,
      check_pass_count INTEGER, check_warn_count INTEGER,
      check_fail_count INTEGER, check_info_count INTEGER, overall_status TEXT,
      new_cols_vs_previous TEXT, missing_cols_vs_previous TEXT,
      new_cols_vs_schema TEXT, missing_cols_vs_schema TEXT,
      comparison_mode TEXT NOT NULL DEFAULT 'comparison',
      render_status TEXT NOT NULL DEFAULT 'success',
      type_changed_cols_vs_previous TEXT)")
  DBI::dbExecute(con, "
    CREATE TABLE column_snapshots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      snapshot_id INTEGER NOT NULL REFERENCES snapshots(id),
      column_name TEXT NOT NULL, dq_check TEXT NOT NULL,
      value TEXT, threshold TEXT, severity_on_breach TEXT)")
  rows <- list(c(mr_prev, nn_prev), c(mr_curr, nn_curr))
  for (i in 1:2) {
    DBI::dbExecute(con,
      "INSERT INTO snapshots (dataset_name, run_timestamp, file_name,
         row_count, col_count, check_pass_count, check_warn_count,
         check_fail_count, check_info_count, overall_status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      list("rate_ds", sprintf("2025-0%d-01T09:00:00Z", i),
           sprintf("d0%d.csv", i), 1000L, 1L, 1L, 0L, 0L, 0L, "PASS"))
    sid <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
    DBI::dbAppendTable(con, "column_snapshots", data.frame(
      snapshot_id = sid, column_name = "amt",
      dq_check = c("inferred_type", "missing_rate", "non_numeric_rate"),
      value    = c("numeric", as.character(rows[[i]][1]), as.character(rows[[i]][2])),
      threshold = NA_character_, severity_on_breach = NA_character_,
      stringsAsFactors = FALSE))
  }
  db
}

test_that("a large decrease in missing / non-numeric rate does not breach (B-44)", {
  # -9 pp missing, -4.5 pp non-numeric: improvements, well past the thresholds.
  db      <- make_rate_drift_db(mr_prev = 0.10, mr_curr = 0.01,
                                nn_prev = 0.05, nn_curr = 0.005)
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("rate_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)

  mr <- drift$missing_rate_changes[drift$missing_rate_changes$Column == "amt", ]
  expect_lt(mr$missing_rate_change_pp, 0)     # it decreased
  expect_false(mr$missing_rate_exceeds)       # ...so it must not be flagged

  nn <- drift$non_numeric_changes[drift$non_numeric_changes$Column == "amt", ]
  expect_lt(nn$non_numeric_rate_change_pp, 0)
  expect_false(nn$non_numeric_rate_exceeds)
})

test_that("a large increase in missing / non-numeric rate still breaches (B-44)", {
  db      <- make_rate_drift_db(mr_prev = 0.01, mr_curr = 0.10,
                                nn_prev = 0.005, nn_curr = 0.05)
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("rate_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)

  mr <- drift$missing_rate_changes[drift$missing_rate_changes$Column == "amt", ]
  expect_gt(mr$missing_rate_change_pp, 0)
  expect_true(mr$missing_rate_exceeds)

  nn <- drift$non_numeric_changes[drift$non_numeric_changes$Column == "amt", ]
  expect_gt(nn$non_numeric_rate_change_pp, 0)
  expect_true(nn$non_numeric_rate_exceeds)
})

# -- G-05/G-06: dataset-level threshold override -------------------------------

test_that("compare_snapshots() applies dataset-level threshold overrides (G-05)", {
  tmp_cfg     <- withr::local_tempdir()
  db          <- make_drift_db(2)
  db_fwd      <- normalizePath(db,      winslash = "/", mustWork = FALSE)
  tmp_cfg_fwd <- normalizePath(tmp_cfg, winslash = "/", mustWork = FALSE)

  writeLines(c(
    sprintf('snapshot_db: "%s"', db_fwd),
    sprintf('report_output_dir: "%s"', tmp_cfg_fwd),
    'default_rules:',
    '  max_missing_rate_change_pp: 2.0',
    '  max_numeric_mean_shift_pct: 0.20',
    '  max_non_numeric_rate_change_pp: 1.0',
    '  max_row_count_change_pct: 0.10'
  ), file.path(tmp_cfg, "dqcheckr.yml"))

  writeLines(c(
    'dataset_name: "test_ds"',
    'format: csv',
    'encoding: "UTF-8"',
    sprintf('snapshot_db: "%s"', db_fwd),
    sprintf('report_output_dir: "%s"', tmp_cfg_fwd),
    'rule_overrides:',
    '  max_numeric_mean_shift_pct: 0.01'
  ), file.path(tmp_cfg, "test_ds.yml"))

  drift <- compare_snapshots("test_ds", db_path = db,
                             config_dir = tmp_cfg, report = FALSE)
  expect_true(drift$mean_shifts[drift$mean_shifts$Column == "amount",
                                "numeric_mean_exceeds"])
})


# -- Snapshot IDs validated against the dataset (0.2.3, L-04) ---------------------

test_that("compare_snapshots() rejects snapshot IDs from another dataset", {
  db  <- tempfile(fileext = ".sqlite")
  tmp <- tempfile("cfg_"); dir.create(tmp)
  on.exit({ unlink(db); unlink(tmp, recursive = TRUE) })
  writeLines(sprintf("snapshot_db: '%s'", db), file.path(tmp, "dqcheckr.yml"))

  for (i in 1:2) {
    write_snapshot(db, "ds_a", "a.csv", make_accounts_df(),
                   list(), list(), list(), base_config())
    write_snapshot(db, "ds_b", "b.csv", make_accounts_df(),
                   list(), list(), list(), base_config())
  }
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  ids_b <- DBI::dbGetQuery(con,
    "SELECT id FROM snapshots WHERE dataset_name = 'ds_b'")$id
  DBI::dbDisconnect(con)

  expect_error(
    compare_snapshots("ds_a",
                      snapshot_id_prev = ids_b[1], snapshot_id_curr = ids_b[2],
                      db_path = db, config_dir = tmp, report = FALSE),
    class = "dqcheckr_not_found")
})
