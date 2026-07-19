# run_dq_check() validation wiring (plan step 5): error findings abort with
# dqcheckr_validation_error BEFORE any snapshot row exists; warnings surface
# via message() and the run proceeds; read-failure conditions are typed; the
# validation abort wins deterministically over later pipeline aborts.

# A runnable deployment in a temp dir: real data file, minimal valid configs.
# `dataset_extra` appends YAML lines to the dataset config.
make_run_fixture <- function(dataset_extra = character()) {
  root <- file.path(tempdir(), paste0("runval_", sample.int(1e9, 1)))
  dir.create(root)
  data_file <- file.path(root, "data.csv")
  writeLines(c("id,amount", "A1,10", "A2,20", "A3,30"), data_file)
  db <- file.path(root, "snap.sqlite")
  writeLines(c(sprintf('snapshot_db: "%s"', gsub("\\\\", "/", db)),
               sprintf('report_output_dir: "%s"', gsub("\\\\", "/", root))),
             file.path(root, "dqcheckr.yml"))
  writeLines(c('dataset_name: "demo"', "format: csv",
               sprintf('current_file: "%s"', gsub("\\\\", "/", data_file)),
               dataset_extra),
             file.path(root, "demo.yml"))
  list(root = root, db = db, data_file = data_file)
}

snapshot_rows <- function(db) {
  if (!file.exists(db)) return(0L)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con))
  if (!"snapshots" %in% DBI::dbListTables(con)) return(0L)
  DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM snapshots")$n
}

# -- error findings abort, typed, with no snapshot row -------------------------

test_that("an error-severity finding aborts with dqcheckr_validation_error and writes no snapshot", {
  fx <- make_run_fixture("col_names: [id, amount, id]")   # duplicate name: error
  on.exit(unlink(fx$root, recursive = TRUE))
  expect_error(
    run_dq_check("demo", config_dir = fx$root, open_report = FALSE),
    class = "dqcheckr_validation_error")
  expect_equal(snapshot_rows(fx$db), 0L)                  # aborted pre-insert
})

test_that("the abort message carries the validator's findings, not a generic wrapper", {
  fx <- make_run_fixture(c("rule_overrides:", "  max_missing_rate: 7"))
  on.exit(unlink(fx$root, recursive = TRUE))
  err <- tryCatch(
    run_dq_check("demo", config_dir = fx$root, open_report = FALSE),
    error = function(e) e)
  expect_s3_class(err, "dqcheckr_validation_error")
  expect_match(conditionMessage(err), "failed validation")
  expect_match(conditionMessage(err), "max_missing_rate")   # the actual finding
  expect_match(conditionMessage(err), "demo.yml")           # and its file
})

test_that("multiple error findings all appear in one abort message", {
  fx <- make_run_fixture(c("col_names: [id, amount, id]",
                           "rule_overrides:", "  max_missing_rate: 7"))
  on.exit(unlink(fx$root, recursive = TRUE))
  err <- tryCatch(
    run_dq_check("demo", config_dir = fx$root, open_report = FALSE),
    error = function(e) e)
  expect_match(conditionMessage(err), "duplicate")
  expect_match(conditionMessage(err), "max_missing_rate")
})

# -- warnings surface but do not block -----------------------------------------

test_that("warning-severity findings message() and the run completes with a snapshot", {
  fx <- make_run_fixture('some_custom_note: "kept"')       # unknown key: warning
  on.exit(unlink(fx$root, recursive = TRUE))
  expect_message(
    result <- suppressWarnings(
      run_dq_check("demo", config_dir = fx$root, open_report = FALSE)),
    regexp = "validation warnings.*some_custom_note")
  expect_equal(snapshot_rows(fx$db), 1L)
  expect_false(is.null(result$snapshot_id))
})

test_that("a clean config runs with no validation message at all", {
  fx <- make_run_fixture("key_columns: [id]")
  on.exit(unlink(fx$root, recursive = TRUE))
  msgs <- capture_messages(suppressWarnings(
    run_dq_check("demo", config_dir = fx$root, open_report = FALSE)))
  expect_false(any(grepl("validation warnings", msgs)))
  expect_equal(snapshot_rows(fx$db), 1L)
})

# -- typed read-failure conditions now guard the run path ----------------------

test_that("a corrupt dataset YAML aborts the run with dqcheckr_config_parse_error", {
  # Closes the step-1 finding: this used to propagate yaml's raw untyped error
  # out of load_config().
  fx <- make_run_fixture()
  on.exit(unlink(fx$root, recursive = TRUE))
  writeLines("format: [unclosed", file.path(fx$root, "demo.yml"))
  expect_error(
    run_dq_check("demo", config_dir = fx$root, open_report = FALSE),
    class = "dqcheckr_config_parse_error")
})

test_that("an empty dataset YAML aborts the run with dqcheckr_empty_config", {
  fx <- make_run_fixture()
  on.exit(unlink(fx$root, recursive = TRUE))
  writeLines("", file.path(fx$root, "demo.yml"))
  expect_error(
    run_dq_check("demo", config_dir = fx$root, open_report = FALSE),
    class = "dqcheckr_empty_config")
})

test_that("delivery drift (missing key column) still produces a recorded FAIL run, not an abort", {
  # Tier-2 policy: cross-checks against the delivery warn, never block. A
  # supplier dropping the key column must yield a completed run with a QC-12
  # FAIL snapshot and history row -- the outcome dqcheckr exists to record.
  fx <- make_run_fixture("key_columns: [customer_key]")   # not in the file
  on.exit(unlink(fx$root, recursive = TRUE))
  result <- suppressMessages(suppressWarnings(
    run_dq_check("demo", config_dir = fx$root, open_report = FALSE)))
  expect_equal(result$status, "FAIL")
  expect_equal(snapshot_rows(fx$db), 1L)                  # history row exists
})

# -- precedence: validation wins over later pipeline aborts --------------------

test_that("a validation error wins over a missing delivery file", {
  # Both problems present: broken col_names AND a nonexistent current_file.
  # Validation runs first, so the typed validation error must surface -- not
  # detect_files()'s dqcheckr_missing_file.
  fx <- make_run_fixture("col_names: [id, amount, id]")
  on.exit(unlink(fx$root, recursive = TRUE))
  unlink(fx$data_file)
  expect_error(
    run_dq_check("demo", config_dir = fx$root, open_report = FALSE),
    class = "dqcheckr_validation_error")
})

test_that("with a clean config, a missing delivery still aborts as before (missing_file)", {
  fx <- make_run_fixture()
  on.exit(unlink(fx$root, recursive = TRUE))
  unlink(fx$data_file)   # tier 2 skips; validation passes; detect_files aborts
  expect_error(
    run_dq_check("demo", config_dir = fx$root, open_report = FALSE),
    class = "dqcheckr_missing_file")
  expect_equal(snapshot_rows(fx$db), 0L)
})

# -- regression: the valid path is byte-identical in behaviour -----------------

test_that("a valid config produces the same run result shape as before", {
  fx <- make_run_fixture("key_columns: [id]")
  on.exit(unlink(fx$root, recursive = TRUE))
  result <- suppressMessages(suppressWarnings(
    run_dq_check("demo", config_dir = fx$root, open_report = FALSE)))
  expect_named(result, c("status", "report_path", "snapshot_id"))
  expect_true(result$status %in% c("PASS", "WARN", "FAIL", "INFO"))
  expect_equal(snapshot_rows(fx$db), 1L)
})
