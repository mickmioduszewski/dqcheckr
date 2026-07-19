# list_runs(): name-based wrapper resolving snapshot_db from config and
# delegating to read_recent_snapshots(). The tests cover the path-resolution
# matrix (relative/absolute/inherited/overridden snapshot_db), the delegation
# contract (schema, ordering, n handling), and every failure mode of the
# config-resolution step.

# Write a minimal global + dataset config pair into its own temp dir and return
# the dir. `global`/`dataset` are extra YAML lines appended to each file.
make_list_runs_config <- function(global = character(), dataset = character(),
                                  dataset_name = "demo") {
  cfg_dir <- file.path(tempdir(), paste0("lr_cfg_", sample.int(1e9, 1)))
  dir.create(cfg_dir)
  writeLines(global, file.path(cfg_dir, "dqcheckr.yml"))
  writeLines(c(sprintf('dataset_name: "%s"', dataset_name), "format: csv",
               dataset),
             file.path(cfg_dir, paste0(dataset_name, ".yml")))
  cfg_dir
}

# Seed a snapshot DB with n rows for a dataset, returning the ids in insert
# order. Uses the real write path (write_snapshot) so the fixture can never
# drift from the schema.
seed_snapshots <- function(db, dataset_name, n = 1) {
  df <- data.frame(a = c("1", "2"), b = c("x", "y"), stringsAsFactors = FALSE)
  results <- list(dq_result("QC-01", "Missing rate", column = "a",
                            status = "PASS", observed = "0%", message = "OK"))
  vapply(seq_len(n), function(i) {
    write_snapshot(db, dataset_name, paste0("file_", i, ".csv"),
                   df, results, list(), list(), base_config())
  }, numeric(1))
}

# -- snapshot_db resolution ----------------------------------------------------

test_that("list_runs() resolves an absolute snapshot_db from the dataset config", {
  db  <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  cfg <- make_list_runs_config(
    dataset = sprintf('snapshot_db: "%s"', gsub("\\\\", "/", db)))
  on.exit(unlink(cfg, recursive = TRUE), add = TRUE)

  ids <- seed_snapshots(db, "demo", n = 1)
  res <- list_runs("demo", config_dir = cfg)
  expect_equal(nrow(res), 1L)
  expect_equal(res$id, ids)
})

test_that("list_runs() inherits snapshot_db from the global config", {
  db  <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  cfg <- make_list_runs_config(
    global = sprintf('snapshot_db: "%s"', gsub("\\\\", "/", db)))
  on.exit(unlink(cfg, recursive = TRUE), add = TRUE)

  seed_snapshots(db, "demo", n = 1)
  expect_equal(nrow(list_runs("demo", config_dir = cfg)), 1L)
})

test_that("a dataset-level snapshot_db overrides the global one", {
  db_global  <- tempfile(fileext = ".sqlite")
  db_dataset <- tempfile(fileext = ".sqlite")
  on.exit(unlink(c(db_global, db_dataset)))
  cfg <- make_list_runs_config(
    global  = sprintf('snapshot_db: "%s"', gsub("\\\\", "/", db_global)),
    dataset = sprintf('snapshot_db: "%s"', gsub("\\\\", "/", db_dataset)))
  on.exit(unlink(cfg, recursive = TRUE), add = TRUE)

  seed_snapshots(db_global,  "demo", n = 2)   # decoy: must NOT be read
  seed_snapshots(db_dataset, "demo", n = 1)
  expect_equal(nrow(list_runs("demo", config_dir = cfg)), 1L)
})

test_that("a relative snapshot_db resolves against the working directory (run_dq_check parity)", {
  root <- file.path(tempdir(), paste0("lr_root_", sample.int(1e9, 1)))
  dir.create(file.path(root, "data"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE))
  cfg <- make_list_runs_config(global = 'snapshot_db: "data/snap.sqlite"')
  on.exit(unlink(cfg, recursive = TRUE), add = TRUE)

  old_wd <- setwd(root)
  on.exit(setwd(old_wd), add = TRUE)
  seed_snapshots("data/snap.sqlite", "demo", n = 1)
  expect_equal(nrow(list_runs("demo", config_dir = cfg)), 1L)
})

test_that("snapshot_db absent everywhere falls back to data/snapshots.sqlite (run_dq_check parity)", {
  root <- file.path(tempdir(), paste0("lr_root_", sample.int(1e9, 1)))
  dir.create(file.path(root, "data"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE))
  cfg <- make_list_runs_config()   # no snapshot_db in either file
  on.exit(unlink(cfg, recursive = TRUE), add = TRUE)

  old_wd <- setwd(root)
  on.exit(setwd(old_wd), add = TRUE)
  seed_snapshots("data/snapshots.sqlite", "demo", n = 1)
  expect_equal(nrow(list_runs("demo", config_dir = cfg)), 1L)
})

# -- delegation contract -------------------------------------------------------

test_that("no database file yet returns the empty frame with the full schema", {
  cfg <- make_list_runs_config(
    dataset = sprintf('snapshot_db: "%s"',
                      gsub("\\\\", "/", tempfile(fileext = ".sqlite"))))
  on.exit(unlink(cfg, recursive = TRUE))

  res <- list_runs("demo", config_dir = cfg)
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 0L)
  # Full read_recent_snapshots() schema, pinned by name (the GUI and
  # compare_snapshots() consumers branch on these).
  expect_named(res, c("id", "dataset_name", "run_timestamp", "file_name",
                      "row_count", "col_count",
                      "check_pass_count", "check_warn_count",
                      "check_fail_count", "check_info_count",
                      "overall_status", "new_cols_vs_previous",
                      "missing_cols_vs_previous", "new_cols_vs_schema",
                      "missing_cols_vs_schema", "comparison_mode",
                      "render_status", "type_changed_cols_vs_previous",
                      "report_file"))
})

test_that("dataset with a DB shared by another dataset returns only its own rows", {
  db  <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  cfg <- make_list_runs_config(
    dataset = sprintf('snapshot_db: "%s"', gsub("\\\\", "/", db)))
  on.exit(unlink(cfg, recursive = TRUE), add = TRUE)

  seed_snapshots(db, "demo",  n = 2)
  seed_snapshots(db, "other", n = 3)
  res <- list_runs("demo", config_dir = cfg)
  expect_equal(nrow(res), 2L)
  expect_true(all(res$dataset_name == "demo"))
})

test_that("rows come back most recent first and n caps them", {
  db  <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  cfg <- make_list_runs_config(
    dataset = sprintf('snapshot_db: "%s"', gsub("\\\\", "/", db)))
  on.exit(unlink(cfg, recursive = TRUE), add = TRUE)

  ids <- seed_snapshots(db, "demo", n = 5)
  res <- list_runs("demo", config_dir = cfg, n = 3)
  expect_equal(nrow(res), 3L)
  expect_equal(res$id, rev(ids)[1:3])           # newest first
  expect_equal(nrow(list_runs("demo", config_dir = cfg)), 5L)  # default n = 10
})

test_that("n = 0 and negative n return zero rows (primitive's clamping, not LIMIT -1)", {
  db  <- tempfile(fileext = ".sqlite")
  on.exit(unlink(db))
  cfg <- make_list_runs_config(
    dataset = sprintf('snapshot_db: "%s"', gsub("\\\\", "/", db)))
  on.exit(unlink(cfg, recursive = TRUE), add = TRUE)

  seed_snapshots(db, "demo", n = 2)
  expect_equal(nrow(list_runs("demo", config_dir = cfg, n = 0)),  0L)
  expect_equal(nrow(list_runs("demo", config_dir = cfg, n = -1)), 0L)
})

test_that("list_runs() sees the row written by a full run_dq_check()", {
  skip_if_not_installed("quarto")
  tmp <- gsub("\\\\", "/", file.path(tempdir(), paste0("lr_e2e_", sample.int(1e9, 1))))
  dir.create(tmp, recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE))
  dat <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
  writeLines(c(
    sprintf('snapshot_db: "%s/snap.sqlite"', tmp),
    sprintf('report_output_dir: "%s"', tmp),
    "default_rules:",
    "  max_missing_rate: 0.60",
    "  min_row_count: 5"
  ), file.path(tmp, "dqcheckr.yml"))
  writeLines(c(
    'dataset_name: "starwars_csv"',
    sprintf('current_file: "%s"', dat),
    "format: csv",
    'delimiter: ","'
  ), file.path(tmp, "starwars_csv.yml"))

  result <- suppressMessages(suppressWarnings(
    run_dq_check("starwars_csv", config_dir = tmp, open_report = FALSE)))
  res <- list_runs("starwars_csv", config_dir = tmp)
  expect_equal(nrow(res), 1L)
  expect_equal(res$id, result$snapshot_id)
})

test_that(".default_paths is the single source of both path defaults", {
  # The documented defaults, pinned: changing them must be a conscious act that
  # touches this test, and every resolution site reads this constant (no
  # re-hardcoded literals -- the pre-0.3.0 state had four independent copies).
  expect_equal(.default_paths$snapshot_db,       "data/snapshots.sqlite")
  expect_equal(.default_paths$report_output_dir, "reports/")
})

# -- failure modes of the config-resolution step -------------------------------

test_that("missing dataset config aborts with dqcheckr_missing_file", {
  cfg <- make_list_runs_config()
  on.exit(unlink(cfg, recursive = TRUE))
  expect_error(list_runs("no_such_dataset", config_dir = cfg),
               class = "dqcheckr_missing_file")
})

test_that("missing global config aborts with dqcheckr_missing_file", {
  cfg <- make_list_runs_config()
  on.exit(unlink(cfg, recursive = TRUE))
  unlink(file.path(cfg, "dqcheckr.yml"))
  expect_error(list_runs("demo", config_dir = cfg),
               class = "dqcheckr_missing_file")
})

test_that("nonexistent config_dir aborts with dqcheckr_missing_file", {
  expect_error(list_runs("demo", config_dir = tempfile()),
               class = "dqcheckr_missing_file")
})

test_that("corrupt dataset YAML surfaces a parse error rather than an empty result", {
  cfg <- make_list_runs_config()
  on.exit(unlink(cfg, recursive = TRUE))
  writeLines(c("dataset_name: \"demo\"", "format: [unclosed"),
             file.path(cfg, "demo.yml"))
  # list_runs() reads via load_config(), which lets the yaml parser's error
  # propagate raw -- unlike the run path, which validates first and aborts
  # typed. What matters here is that the failure is loud, not silently mapped
  # to "no runs".
  expect_error(list_runs("demo", config_dir = cfg), regexp = "Parser|Scanner|yaml")
})

test_that("unreadable DB file warns (read failure is not 'no history') and returns empty", {
  db <- tempfile(fileext = ".sqlite")
  writeLines("this is not a sqlite database, padded to pass the header sniff",
             db)   # exists but is not SQLite
  on.exit(unlink(db))
  cfg <- make_list_runs_config(
    dataset = sprintf('snapshot_db: "%s"', gsub("\\\\", "/", db)))
  on.exit(unlink(cfg, recursive = TRUE), add = TRUE)

  # RSQLite also warns about synchronous mode on the broken file before the
  # read fails, so collect all warnings rather than expecting exactly one.
  warns <- capture_warnings(res <- list_runs("demo", config_dir = cfg))
  expect_true(any(grepl("Could not read snapshot history", warns)))
  expect_equal(nrow(res), 0L)
})
