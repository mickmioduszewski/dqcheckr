make_drift_db <- function(n_snapshots = 2) {
  db  <- tempfile(fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  on.exit(DBI::dbDisconnect(con))

  DBI::dbExecute(con, "
    CREATE TABLE snapshots (
      id               INTEGER PRIMARY KEY AUTOINCREMENT,
      dataset_name     TEXT, run_timestamp TEXT, file_name TEXT,
      row_count        INTEGER, col_count INTEGER,
      check_pass_count INTEGER, check_warn_count INTEGER,
      check_fail_count INTEGER, check_info_count INTEGER,
      overall_status   TEXT,
      new_cols_vs_previous TEXT, missing_cols_vs_previous TEXT,
      new_cols_vs_schema TEXT, missing_cols_vs_schema TEXT,
      comparison_mode  TEXT NOT NULL DEFAULT 'comparison',
      render_status    TEXT NOT NULL DEFAULT 'success',
      type_changed_cols_vs_previous TEXT
    )")

  DBI::dbExecute(con, "
    CREATE TABLE column_snapshots (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      snapshot_id INTEGER NOT NULL REFERENCES snapshots(id),
      column_name TEXT NOT NULL, dq_check TEXT NOT NULL,
      value TEXT, threshold TEXT, severity_on_breach TEXT
    )")

  for (i in seq_len(n_snapshots)) {
    DBI::dbExecute(con,
      "INSERT INTO snapshots
       (dataset_name, run_timestamp, file_name,
        row_count, col_count,
        check_pass_count, check_warn_count, check_fail_count, check_info_count,
        overall_status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      list("test_ds",
           sprintf("2025-0%d-01T09:00:00Z", i),
           sprintf("delivery_0%d.csv", i),
           1000L * i, 3L,
           10L, 0L, 0L, 2L,
           "PASS"))

    snap_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id

    stats <- data.frame(
      snapshot_id        = snap_id,
      column_name        = c("amount", "amount", "amount", "amount",
                             "status", "status", "status",
                             "dt",     "dt",     "dt"),
      dq_check           = c("inferred_type", "missing_rate",
                             "numeric_parseable_mean", "distinct_count",
                             "inferred_type", "missing_rate", "distinct_count",
                             "inferred_type", "missing_rate", "distinct_count"),
      value              = c("numeric",
                             as.character(0.01 * i),
                             as.character(100 * i),
                             as.character(50L * i),
                             "character",
                             as.character(0.00),
                             as.character(3L),
                             "date",
                             as.character(0.00),
                             as.character(10L * i)),
      threshold          = NA_character_,
      severity_on_breach = NA_character_,
      stringsAsFactors   = FALSE
    )
    DBI::dbAppendTable(con, "column_snapshots", stats)
  }

  db
}

make_drift_config <- function(dir = tempdir()) {
  writeLines(c(
    'snapshot_db: "data/snapshots.sqlite"',
    paste0('report_output_dir: "', dir, '"'),
    'default_rules:',
    '  max_missing_rate_change_pp: 2.0',
    '  max_numeric_mean_shift_pct: 0.20',
    '  max_non_numeric_rate_change_pp: 1.0',
    '  max_row_count_change_pct: 0.10'
  ), file.path(dir, "dqcheckr.yml"))
  dir
}
