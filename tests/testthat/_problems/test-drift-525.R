# Extracted from test-drift.R:525

# prequel ----------------------------------------------------------------------
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

# test -------------------------------------------------------------------------
expect_equal(.column_mean_shift_overrides(list(amount = 0.05)), numeric(0))
