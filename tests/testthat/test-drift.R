# --- list_snapshots() ---------------------------------------------------------

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

# --- compare_snapshots() errors -----------------------------------------------

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

# --- compare_snapshots() default ID selection ---------------------------------

test_that("compare_snapshots defaults to second-latest vs latest", {
  db      <- make_drift_db(3)
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)
  expect_equal(drift$snap_prev$id, 2L)
  expect_equal(drift$snap_curr$id, 3L)
})

test_that("compare_snapshots respects explicit ID order even if reversed", {
  db      <- make_drift_db(2)
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds",
                               snapshot_id_prev = 2L, snapshot_id_curr = 1L,
                               db_path = db, config_dir = cfg_dir, report = FALSE)
  expect_equal(drift$snap_prev$id, 2L)
  expect_equal(drift$snap_curr$id, 1L)
})

# --- drift list structure -----------------------------------------------------

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

# --- compute_drift: table-level -----------------------------------------------

test_that("table_drift row count change is correct", {
  db      <- make_drift_db(2)
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)
  td <- drift$table_drift
  row_row <- td[td$Metric == "Row count", ]
  expect_equal(row_row$Previous, 1000L)
  expect_equal(row_row$Current,  2000L)
  expect_equal(row_row$Change,   1000L)
  # 100% increase — exceeds 10% threshold
  expect_equal(row_row$Exceeds, "***")
})

# --- compute_drift: schema drift ---------------------------------------------

test_that("schema_changes detects new column across snapshots", {
  db  <- make_drift_db(2)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  # Add a column that appears only in snapshot 2
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
  # Change 'amount' type in snapshot 2 to character
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

# --- compute_drift: per-column ------------------------------------------------

test_that("missing_rate_changes is filtered to changed columns only", {
  db      <- make_drift_db(2)
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)
  # status column has 0% missing in both snapshots — should not appear
  expect_false("status" %in% drift$missing_rate_changes$Column)
})

test_that("missing_rate_changes sorted by magnitude descending", {
  db      <- make_drift_db(2)
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)
  mr <- drift$missing_rate_changes
  if (nrow(mr) > 1) {
    expect_true(all(diff(abs(mr$missing_rate_change_pp)) <= 0))
  }
})

test_that("mean_shifts numeric_mean computed correctly", {
  db      <- make_drift_db(2)
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)
  ms <- drift$mean_shifts[drift$mean_shifts$Column == "amount", ]
  # prev mean = 100, curr mean = 200 => shift = 100%
  expect_equal(ms$numeric_mean_prev, 100)
  expect_equal(ms$numeric_mean_curr, 200)
  expect_equal(ms$numeric_mean_shift_pct, 1.0)
  expect_true(ms$numeric_mean_exceeds)  # 100% > 20% threshold
})

test_that("distinct_changes filtered to changed columns only", {
  db      <- make_drift_db(2)
  cfg_dir <- make_drift_config()
  drift   <- compare_snapshots("test_ds", db_path = db,
                               config_dir = cfg_dir, report = FALSE)
  # status has distinct_count = 3 in both snapshots — should not appear
  expect_false("status" %in% drift$distinct_changes$Column)
})
